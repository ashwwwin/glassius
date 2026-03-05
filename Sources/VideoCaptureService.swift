@preconcurrency import AVFoundation
@preconcurrency import CoreImage
@preconcurrency import Foundation
import ImageIO
import UniformTypeIdentifiers

final class VideoCaptureService: NSObject, @unchecked Sendable {
    var onEncodedFrame: (@Sendable (Data) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "glassius.capture.session.queue")
    private let outputQueue = DispatchQueue(label: "glassius.capture.output.queue", qos: .userInitiated)
    private let ciContext = CIContext(options: nil)

    private var configured = false
    private var lastFrameTime: CFTimeInterval = 0

    private let maxPreviewDimension: CGFloat = 320
    private let jpegQuality: CGFloat = 0.25
    private let maxFramesPerSecond: Double = 6
    private let maxFrameBytes = 48 * 1024
    private var runToken: UInt64 = 0

    func start(completion: @escaping @Sendable (Bool) -> Void) {
        sessionQueue.async {
            self.runToken += 1
            let token = self.runToken

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                completion(self.startSessionLocked(token: token))
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else {
                        completion(false)
                        return
                    }

                    guard granted else {
                        completion(false)
                        return
                    }

                    self.sessionQueue.async {
                        completion(self.startSessionLocked(token: token))
                    }
                }
            case .denied, .restricted:
                self.emitStatus("Camera access denied. Enable it in System Settings > Privacy & Security > Camera.")
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.runToken += 1
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func startSessionLocked(token: UInt64) -> Bool {
        guard token == runToken else {
            return false
        }

        guard configureSessionIfNeededLocked() else { return false }

        if !session.isRunning {
            session.startRunning()
        }

        emitStatus("Camera is streaming.")
        return true
    }

    private func configureSessionIfNeededLocked() -> Bool {
        if configured {
            return true
        }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        defer {
            session.commitConfiguration()
        }

        do {
            guard let camera = AVCaptureDevice.default(for: .video) else {
                emitStatus("No camera found.")
                return false
            }

            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                emitStatus("Could not attach camera input.")
                return false
            }

            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: outputQueue)

            guard session.canAddOutput(output) else {
                emitStatus("Could not attach camera output.")
                return false
            }

            session.addOutput(output)

            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }

            configured = true
            return true
        } catch {
            emitStatus("Camera configuration failed: \(error.localizedDescription)")
            return false
        }
    }

    private func emitStatus(_ status: String) {
        let callback = onStatus
        DispatchQueue.main.async {
            callback?(status)
        }
    }

    private func shouldProcessFrame(at timestamp: CFTimeInterval) -> Bool {
        let minimumInterval = 1.0 / maxFramesPerSecond
        guard timestamp - lastFrameTime >= minimumInterval else {
            return false
        }

        lastFrameTime = timestamp
        return true
    }

    private func encodeFrame(sampleBuffer: CMSampleBuffer) -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        guard let scaledImage = Self.scaled(cgImage: cgImage, maxDimension: maxPreviewDimension) else {
            return nil
        }

        return Self.constrainedJPEGData(
            from: scaledImage,
            preferredCompression: jpegQuality,
            maxBytes: maxFrameBytes
        )
    }

    private static func scaled(cgImage: CGImage, maxDimension: CGFloat) -> CGImage? {
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let longestEdge = max(sourceWidth, sourceHeight)

        if longestEdge <= maxDimension {
            return cgImage
        }

        let scale = maxDimension / longestEdge
        let targetWidth = max(1, Int(sourceWidth * scale))
        let targetHeight = max(1, Int(sourceHeight * scale))

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private static func jpegData(from cgImage: CGImage, compression: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compression
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    private static func constrainedJPEGData(from cgImage: CGImage, preferredCompression: CGFloat, maxBytes: Int) -> Data? {
        let qualityCandidates: [CGFloat] = [
            preferredCompression,
            0.2,
            0.16,
            0.12,
            0.08
        ]

        for quality in qualityCandidates {
            if let data = jpegData(from: cgImage, compression: quality), data.count <= maxBytes {
                return data
            }
        }

        // As a final fallback, aggressively downscale and retry at low quality.
        if let reduced = scaled(cgImage: cgImage, maxDimension: 240) {
            for quality in [CGFloat(0.12), CGFloat(0.08)] {
                if let data = jpegData(from: reduced, compression: quality), data.count <= maxBytes {
                    return data
                }
            }
        }

        return nil
    }
}

extension VideoCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard shouldProcessFrame(at: now) else {
            return
        }

        guard let data = encodeFrame(sampleBuffer: sampleBuffer) else {
            return
        }

        let callback = onEncodedFrame
        DispatchQueue.main.async {
            callback?(data)
        }
    }
}
