import Foundation

/// macOS opens its own "Captive Network Assistant" on sign-in networks. Switching it off is a system-wide
/// setting that needs an administrator, so Router only does it when asked, and can switch it back on.
extension WiFiManager {
    static let captivePrefs = "/Library/Preferences/SystemConfiguration/com.apple.captive.control"

    static func readNativePortalOff() -> Bool {
        let d = NSDictionary(contentsOfFile: captivePrefs + ".plist")
        return (d?["Active"] as? Bool) == false
    }

    func setNativePortalOff(_ off: Bool) {
        guard !portalSwitchBusy else { return }
        portalSwitchBusy = true
        let cmd = "defaults write \(Self.captivePrefs) Active -bool \(off ? "false" : "true")"
        Task {
            let err: String? = await Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "do shell script \"\(cmd)\" with administrator privileges with prompt \"Router wants to \(off ? "turn off" : "turn back on") the macOS sign-in window for Wi-Fi networks.\""]
                let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
                do { try p.run() } catch { return error.localizedDescription }
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return p.terminationStatus == 0 ? nil : (out.contains("-128") ? "" : out)
            }.value
            nativePortalOff = Self.readNativePortalOff()
            portalSwitchBusy = false
            if let err, !err.isEmpty { error = "Couldn't change the sign-in window setting: \(err.trimmingCharacters(in: .whitespacesAndNewlines))" }
        }
    }
}
