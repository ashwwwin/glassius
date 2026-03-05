import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                VideoPane(
                    image: model.remoteFrame,
                    title: model.connectedPeerNames.isEmpty ? "Friend" : model.connectedPeerNames.joined(separator: ", "),
                    placeholder: model.connectedPeerNames.isEmpty ? "Waiting for a connection" : "Waiting for remote video"
                )
                .frame(width: 390, height: 250)

                VideoPane(
                    image: model.localFrame,
                    title: "You",
                    placeholder: model.localPreviewPlaceholder
                )
                .frame(width: 130, height: 98)
                .padding(10)
            }

            Button("Toggle Fullscreen") {
                model.toggleFullscreenWindow()
            }
            .disabled(model.localFrame == nil && model.remoteFrame == nil)

            if !model.discoveredPeerNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.discoveredPeerNames, id: \.self) { peerName in
                            Button("Connect \(peerName)") {
                                model.connect(to: peerName)
                            }
                            .disabled(model.connectedPeerNames.contains(peerName))
                        }
                    }
                }
            } else {
                Text("No nearby peer discovered yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 414)
    }
}

struct FullscreenVideoView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()

            VideoPane(
                image: model.remoteFrame,
                title: model.connectedPeerNames.isEmpty ? "Friend" : model.connectedPeerNames.joined(separator: ", "),
                placeholder: model.connectedPeerNames.isEmpty ? "Waiting for connection" : "Waiting for remote video"
            )
            .padding(24)

            VideoPane(
                image: model.localFrame,
                title: "You",
                placeholder: model.localPreviewPlaceholder
            )
            .frame(width: 280, height: 190)
            .padding(36)
        }
    }
}

private struct VideoPane: View {
    let image: NSImage?
    let title: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.8))
                    .overlay {
                        Text(placeholder)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 12)
                    }
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GlassiusCam")
                .font(.headline)
            Text("Keep this app running on both Macs to stay connected on your local network.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
