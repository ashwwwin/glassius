import AppKit
import SwiftUI

@main
struct GlassiusCamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = AppModel.shared
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private let model = AppModel.shared
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var suppressNextCloseSync = false
    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        let quitItem = NSMenuItem(title: "Quit Glassius", action: #selector(quitGlassius), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LaunchAtLoginManager.shared.configureDefaultIfNeeded()

        let menuView = MenuContentView(model: model)

        popover.delegate = self
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 430, height: 420)
        popover.contentViewController = NSHostingController(rootView: menuView)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Glassius"
            button.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Glassius")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem

        model.setRemotePopoverVisibilityHandler { [weak self] isShown in
            self?.setPopoverVisible(isShown, syncToPeers: false)
        }
        model.setReturnToMenubarHandler { [weak self] in
            self?.setPopoverVisible(true, syncToPeers: false)
        }
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        if shouldShowContextMenu(for: NSApp.currentEvent) {
            showContextMenu()
            return
        }

        setPopoverVisible(!popover.isShown, syncToPeers: true)
    }

    private func setPopoverVisible(_ shouldShow: Bool, syncToPeers: Bool) {
        guard let button = statusItem?.button else { return }

        if shouldShow, !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            configurePopoverWindowForAllSpaces()
            popover.contentViewController?.view.window?.makeKey()
        } else if !shouldShow, popover.isShown {
            suppressNextCloseSync = true
            popover.performClose(nil)
        }

        model.setLocalPopoverVisibility(shouldShow)

        if syncToPeers {
            model.syncPopoverVisibility(shouldShow)
        }

        model.setSessionActive(shouldShow)
    }

    func popoverDidShow(_ notification: Notification) {
        model.setLocalPopoverVisibility(true)
        model.setSessionActive(true)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setLocalPopoverVisibility(false)
        model.setSessionActive(false)

        if suppressNextCloseSync {
            suppressNextCloseSync = false
            return
        }

        // Sync user-initiated close actions (outside click / escape).
        model.syncPopoverVisibility(false)
    }

    @objc private func quitGlassius() {
        NSApp.terminate(nil)
    }

    private func shouldShowContextMenu(for event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }

        if event.type == .rightMouseUp {
            return true
        }

        if event.type == .leftMouseUp, event.modifierFlags.contains(.control) {
            return true
        }

        return false
    }

    private func showContextMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        statusItem.menu = statusMenu
        button.performClick(nil)
    }

    private func configurePopoverWindowForAllSpaces() {
        guard let window = popover.contentViewController?.view.window else { return }

        var behavior = window.collectionBehavior
        behavior.insert([.canJoinAllSpaces, .moveToActiveSpace, .fullScreenAuxiliary])
        window.collectionBehavior = behavior
        window.level = .floating
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
}
