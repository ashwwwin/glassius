import AppKit
import SwiftUI

@MainActor
final class FullscreenWindowController: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var window: NSWindow?
    var onReturnToMenubarRequested: (() -> Void)?

    private var notifyMenubarOnClose = true

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func toggleFullscreen() {
        guard let window = ensureWindow() else { return }

        if !window.isVisible {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            DispatchQueue.main.async {
                window.toggleFullScreen(nil)
            }
            return
        }

        window.toggleFullScreen(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if notifyMenubarOnClose {
            onReturnToMenubarRequested?()
        }

        window = nil
        notifyMenubarOnClose = true
    }

    func closeWindow() {
        notifyMenubarOnClose = false
        window?.close()
        window = nil
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.deminiaturize(nil)
        notifyMenubarOnClose = true
        closeWindowAndReturnToMenubar()
    }

    private func ensureWindow() -> NSWindow? {
        if let window {
            return window
        }

        guard let model else {
            return nil
        }

        let content = FullscreenVideoView(model: model)
        let hostingView = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Glassius Live"
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces, .moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.isReleasedWhenClosed = false

        self.window = window
        return window
    }

    private func closeWindowAndReturnToMenubar() {
        // Explicit user minimize should behave like close and return to menu bar view.
        notifyMenubarOnClose = true
        window?.close()
        window = nil
    }
}
