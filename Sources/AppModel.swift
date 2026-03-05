import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    var onRemotePopoverVisibilityRequested: ((Bool) -> Void)?
    var onReturnToMenubarRequested: (() -> Void)?

    @Published var localFrame: NSImage?
    @Published var remoteFrame: NSImage?
    @Published var discoveredPeerNames: [String] = []
    @Published var connectedPeerNames: [String] = []
    @Published var isCameraRunning = false
    @Published var isStartingCamera = false
    @Published private(set) var isSessionActive = false
    @Published var statusMessage = "Open Glassius to start video."

    private let captureService = VideoCaptureService()
    private let peerService = PeerVideoService()
    private lazy var fullscreenController: FullscreenWindowController = {
        let controller = FullscreenWindowController(model: self)
        controller.onReturnToMenubarRequested = { [weak self] in
            self?.handleFullscreenDismissedToMenubar()
        }
        return controller
    }()
    private var localPopoverVisibility = false
    private var pendingRemotePopoverVisibility: Bool?
    private var pendingReturnToMenubarRequest = false
    var localPreviewPlaceholder: String {
        if !isSessionActive {
            return "Video off"
        }

        if isStartingCamera {
            return "Starting camera..."
        }

        if isCameraRunning {
            return "Waiting for preview..."
        }

        return "Camera off"
    }

    init() {
        bindServices()
        captureService.warmUp()
        peerService.start()
    }

    func connect(to peerName: String) {
        peerService.connect(toDisplayName: peerName)
    }

    func toggleFullscreenWindow(syncToPeers: Bool = true) {
        fullscreenController.toggleFullscreen()
        if syncToPeers {
            peerService.sendFullscreenToggle()
        }
    }

    func syncPopoverVisibility(_ isShown: Bool) {
        localPopoverVisibility = isShown
        peerService.send(popoverVisibility: isShown)
    }

    func setLocalPopoverVisibility(_ isShown: Bool) {
        localPopoverVisibility = isShown
    }

    func isFullscreenWindowVisible() -> Bool {
        fullscreenController.isWindowVisible
    }

    func setSessionActive(_ active: Bool) {
        guard active != isSessionActive else { return }
        isSessionActive = active

        if active {
            statusMessage = "Starting camera..."
            startCamera()
            return
        }

        captureService.stop()
        isStartingCamera = false
        isCameraRunning = false
        localFrame = nil
        remoteFrame = nil
        fullscreenController.closeWindow()
        statusMessage = "Video is off."
    }

    func setRemotePopoverVisibilityHandler(_ handler: @escaping (Bool) -> Void) {
        onRemotePopoverVisibilityRequested = handler

        if let pendingRemotePopoverVisibility {
            handler(pendingRemotePopoverVisibility)
            self.pendingRemotePopoverVisibility = nil
        }
    }

    func setReturnToMenubarHandler(_ handler: @escaping () -> Void) {
        onReturnToMenubarRequested = handler

        if pendingReturnToMenubarRequest {
            pendingReturnToMenubarRequest = false
            handler()
        }
    }

    private func startCamera() {
        guard !isStartingCamera else { return }
        isStartingCamera = true
        captureService.start { [weak self] started in
            self?.handleCameraStarted(started)
        }
    }

    private func bindServices() {
        captureService.onEncodedFrame = { [weak self] data in
            self?.handleEncodedFrame(data)
        }

        captureService.onStatus = { [weak self] message in
            self?.handleStatus(message)
        }

        peerService.onRemoteFrameData = { [weak self] data in
            self?.handleRemoteFrame(data)
        }

        peerService.onDiscoveredPeerNamesChanged = { [weak self] peerNames in
            self?.handleDiscoveredPeers(peerNames)
        }

        peerService.onConnectedPeerNamesChanged = { [weak self] peerNames in
            self?.handleConnectedPeers(peerNames)
        }

        peerService.onRemotePopoverVisibilityChanged = { [weak self] isShown in
            self?.handleRemotePopoverVisibility(isShown)
        }

        peerService.onRemoteFullscreenToggleRequested = { [weak self] in
            self?.handleRemoteFullscreenToggle()
        }

        peerService.onStatus = { [weak self] message in
            self?.handleStatus(message)
        }
    }

    nonisolated private func handleCameraStarted(_ started: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isSessionActive else { return }
            self.isStartingCamera = false
            self.isCameraRunning = started
            if !started {
                self.localFrame = nil
            }
            self.statusMessage = started ? "Camera ready. Discovering nearby Macs..." : "Camera access denied."
        }
    }

    nonisolated private func handleEncodedFrame(_ data: Data) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isSessionActive else { return }
            self.isStartingCamera = false
            self.localFrame = NSImage(data: data)
            self.peerService.send(frame: data)
        }
    }

    nonisolated private func handleRemoteFrame(_ data: Data) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isSessionActive else { return }
            self.remoteFrame = NSImage(data: data)
        }
    }

    nonisolated private func handleDiscoveredPeers(_ peerNames: [String]) {
        Task { @MainActor [weak self] in
            self?.discoveredPeerNames = peerNames
        }
    }

    nonisolated private func handleConnectedPeers(_ peerNames: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            self.connectedPeerNames = peerNames
            if peerNames.isEmpty {
                self.remoteFrame = nil
                return
            }

            // Reconcile remote popover state after reconnect/new connection.
            self.peerService.send(popoverVisibility: self.localPopoverVisibility)
        }
    }

    nonisolated private func handleStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.statusMessage = message
        }
    }

    nonisolated private func handleRemotePopoverVisibility(_ isShown: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let handler = self.onRemotePopoverVisibilityRequested {
                handler(isShown)
            } else {
                self.pendingRemotePopoverVisibility = isShown
            }
        }
    }

    nonisolated private func handleRemoteFullscreenToggle() {
        Task { @MainActor [weak self] in
            self?.toggleFullscreenWindow(syncToPeers: false)
        }
    }

    nonisolated private func handleFullscreenDismissedToMenubar() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let handler = self.onReturnToMenubarRequested {
                handler()
            } else {
                self.pendingReturnToMenubarRequest = true
            }
        }
    }
}
