import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let configuredKey = "glassius.launchAtLoginConfigured.v1"
    private let fallbackAgentLabel = "local.glassius.cam.launchatlogin"

    private init() {}

    func configureDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey) else { return }

        if enableViaServiceManagement() || enableViaLaunchAgentFallback() {
            defaults.set(true, forKey: configuredKey)
        }
    }

    private func enableViaServiceManagement() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        let service = SMAppService.mainApp
        if service.status == .enabled {
            return true
        }

        do {
            try service.register()
            return true
        } catch {
            return false
        }
    }

    private func enableViaLaunchAgentFallback() -> Bool {
        guard let executablePath = Bundle.main.executablePath else {
            return false
        }

        let agentDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = agentDir.appendingPathComponent("\(fallbackAgentLabel).plist")

        let plist: [String: Any] = [
            "Label": fallbackAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": ["Aqua"]
        ]

        do {
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: plistURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
