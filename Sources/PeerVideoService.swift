@preconcurrency import Foundation
@preconcurrency import MultipeerConnectivity

final class PeerVideoService: NSObject, @unchecked Sendable {
    private let serviceType = "glasscamchat"
    private let controlPrefix = "GLASSIUS_CTRL:"
    private let queue = DispatchQueue(label: "glassius.peer.service.queue")

    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    private var discoveredPeers: [MCPeerID] = []
    private var invitedPeerKeys = Set<String>()
    private var isRunning = false
    private var pendingFrameData: Data?
    private var isFramePumpScheduled = false

    private enum ControlCommand {
        case popover(Bool)
        case fullscreenToggle
    }

    var onRemoteFrameData: (@Sendable (Data) -> Void)?
    var onRemotePopoverVisibilityChanged: (@Sendable (Bool) -> Void)?
    var onRemoteFullscreenToggleRequested: (@Sendable () -> Void)?
    var onDiscoveredPeerNamesChanged: (@Sendable ([String]) -> Void)?
    var onConnectedPeerNamesChanged: (@Sendable ([String]) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?

    override init() {
        let localName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let trimmedName = String(localName.prefix(63))

        peerID = MCPeerID(displayName: trimmedName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .optional)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        queue.async {
            guard !self.isRunning else { return }

            self.isRunning = true
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
            self.emitStatus("Searching for nearby friends...")
        }
    }

    func stop() {
        queue.async {
            guard self.isRunning else { return }

            self.isRunning = false
            self.advertiser.stopAdvertisingPeer()
            self.browser.stopBrowsingForPeers()
            self.session.disconnect()

            self.discoveredPeers.removeAll()
            self.invitedPeerKeys.removeAll()
            self.pendingFrameData = nil
            self.isFramePumpScheduled = false

            self.emitDiscoveredPeers()
            self.emitConnectedPeers()
        }
    }

    func connect(toDisplayName displayName: String) {
        queue.async {
            guard let peer = self.discoveredPeers.first(where: { $0.displayName == displayName }) else {
                self.emitStatus("Peer not available anymore.")
                return
            }

            self.invite(peer: peer, force: true, status: "Connecting to \(peer.displayName)...")
        }
    }

    func send(frame data: Data) {
        queue.async {
            guard self.isRunning else { return }
            // Always keep only the newest frame to avoid latency build-up.
            self.pendingFrameData = data
            self.scheduleFramePumpIfNeededLocked()
        }
    }

    func send(popoverVisibility isShown: Bool) {
        queue.async {
            guard self.isRunning else { return }

            let connectedPeers = self.session.connectedPeers
            guard !connectedPeers.isEmpty else { return }

            let command = self.controlPrefix + (isShown ? "popover_open" : "popover_close")
            guard let payload = command.data(using: .utf8) else { return }

            do {
                try self.session.send(payload, toPeers: connectedPeers, with: .reliable)
            } catch {
                self.emitStatus("Control send failed: \(error.localizedDescription)")
            }
        }
    }

    func sendFullscreenToggle() {
        queue.async {
            guard self.isRunning else { return }

            let connectedPeers = self.session.connectedPeers
            guard !connectedPeers.isEmpty else { return }

            let command = self.controlPrefix + "fullscreen_toggle"
            guard let payload = command.data(using: .utf8) else { return }

            do {
                try self.session.send(payload, toPeers: connectedPeers, with: .reliable)
            } catch {
                self.emitStatus("Control send failed: \(error.localizedDescription)")
            }
        }
    }

    private func invite(peer: MCPeerID, force: Bool, status: String) {
        let peerKey = key(for: peer)
        if !force, invitedPeerKeys.contains(peerKey) {
            return
        }

        invitedPeerKeys.insert(peerKey)
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 5)
        emitStatus(status)
    }

    private func addDiscoveredPeer(_ peer: MCPeerID) {
        guard peer != peerID else { return }
        guard !discoveredPeers.contains(peer) else { return }

        discoveredPeers.append(peer)
        discoveredPeers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        emitDiscoveredPeers()

        if !session.connectedPeers.contains(peer) {
            invite(peer: peer, force: false, status: "Found \(peer.displayName). Sending invite...")
        }
    }

    private func removeDiscoveredPeer(_ peer: MCPeerID) {
        discoveredPeers.removeAll { $0 == peer }
        invitedPeerKeys.remove(key(for: peer))
        emitDiscoveredPeers()
    }

    private func emitDiscoveredPeers() {
        let peerNames = discoveredPeers.map(\.displayName).sorted()
        let callback = onDiscoveredPeerNamesChanged
        DispatchQueue.main.async {
            callback?(peerNames)
        }
    }

    private func emitConnectedPeers() {
        let peerNames = session.connectedPeers.map(\.displayName).sorted()
        let callback = onConnectedPeerNamesChanged
        DispatchQueue.main.async {
            callback?(peerNames)
        }
    }

    private func emitRemoteFrame(_ data: Data) {
        let callback = onRemoteFrameData
        DispatchQueue.main.async {
            callback?(data)
        }
    }

    private func emitStatus(_ message: String) {
        let callback = onStatus
        DispatchQueue.main.async {
            callback?(message)
        }
    }

    private func emitRemotePopoverVisibility(_ isShown: Bool) {
        let callback = onRemotePopoverVisibilityChanged
        DispatchQueue.main.async {
            callback?(isShown)
        }
    }

    private func emitRemoteFullscreenToggle() {
        let callback = onRemoteFullscreenToggleRequested
        DispatchQueue.main.async {
            callback?()
        }
    }

    private func decodeControl(from data: Data) -> ControlCommand? {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix(controlPrefix) else {
            return nil
        }

        let command = String(text.dropFirst(controlPrefix.count))
        switch command {
        case "popover_open":
            return .popover(true)
        case "popover_close":
            return .popover(false)
        case "fullscreen_toggle":
            return .fullscreenToggle
        default:
            return nil
        }
    }

    private func key(for peer: MCPeerID) -> String {
        "\(peer.displayName)#\(peer.hash)"
    }

    private func scheduleReconnectInvite(for peer: MCPeerID) {
        queue.asyncAfter(deadline: .now() + 1.0) {
            guard self.isRunning else { return }
            guard self.discoveredPeers.contains(peer) else { return }
            guard !self.session.connectedPeers.contains(peer) else { return }

            self.invite(peer: peer, force: false, status: "Reconnecting to \(peer.displayName)...")
        }
    }

    private func scheduleFramePumpIfNeededLocked() {
        guard !isFramePumpScheduled else { return }
        isFramePumpScheduled = true
        queue.async {
            self.sendLatestFrameIfNeededLocked()
        }
    }

    private func sendLatestFrameIfNeededLocked() {
        isFramePumpScheduled = false

        guard isRunning else {
            pendingFrameData = nil
            return
        }

        let peers = session.connectedPeers
        guard !peers.isEmpty else {
            pendingFrameData = nil
            return
        }

        guard let data = pendingFrameData else {
            return
        }

        pendingFrameData = nil

        do {
            // Video should be low-latency; drop stale frames instead of head-of-line blocking.
            try session.send(data, toPeers: peers, with: .unreliable)
        } catch {
            emitStatus("Frame send failed: \(error.localizedDescription)")
        }

        if pendingFrameData != nil {
            scheduleFramePumpIfNeededLocked()
        }
    }
}

extension PeerVideoService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
        queue.async {
            self.emitStatus("Accepted invite from \(peerID.displayName).")
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        queue.async {
            self.emitStatus("Advertising failed: \(error.localizedDescription)")
        }
    }
}

extension PeerVideoService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        queue.async {
            self.addDiscoveredPeer(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        queue.async {
            self.removeDiscoveredPeer(peerID)
            self.emitStatus("Lost \(peerID.displayName).")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        queue.async {
            self.emitStatus("Browsing failed: \(error.localizedDescription)")
        }
    }
}

extension PeerVideoService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        queue.async {
            switch state {
            case .notConnected:
                self.invitedPeerKeys.remove(self.key(for: peerID))
                self.emitStatus("\(peerID.displayName) disconnected.")
                self.scheduleReconnectInvite(for: peerID)
            case .connecting:
                self.emitStatus("\(peerID.displayName) is connecting...")
            case .connected:
                self.invitedPeerKeys.remove(self.key(for: peerID))
                self.emitStatus("Connected to \(peerID.displayName).")
            @unknown default:
                self.emitStatus("Unknown connection state from \(peerID.displayName).")
            }

            self.emitConnectedPeers()
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let controlCommand = decodeControl(from: data) {
            switch controlCommand {
            case .popover(let shouldShowPopover):
                emitRemotePopoverVisibility(shouldShowPopover)
            case .fullscreenToggle:
                emitRemoteFullscreenToggle()
            }
            return
        }

        emitRemoteFrame(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}
