import Foundation

/// What Router knows about the user's VPN. Only Tailscale is controlled; anything else is just detected.
struct VPNState: Equatable {
    var installed = false
    var running = false
    var exitNode: String?          // host name of the active exit node
    var exitOption: String?        // a node we could use as an exit node
    var exitOptionIP: String?
}

enum Tailscale {
    static let bin = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    static var installed: Bool { FileManager.default.isExecutableFile(atPath: bin) }

    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 8) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return (false, "Timed out") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    static func state() -> VPNState {
        guard installed else { return VPNState() }
        var s = VPNState(installed: true)
        let r = run(["status", "--json"])
        guard let d = r.out.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return s }
        s.running = (j["BackendState"] as? String) == "Running"
        guard s.running else { return s }
        if let ex = j["ExitNodeStatus"] as? [String: Any], (ex["Online"] as? Bool) != false {
            let ids = (ex["TailscaleIPs"] as? [String]) ?? []
            let peers = (j["Peer"] as? [String: [String: Any]]) ?? [:]
            s.exitNode = peers.values.first { p in
                ((p["TailscaleIPs"] as? [String]) ?? []).contains { ids.first?.hasPrefix($0) ?? false }
            }?["HostName"] as? String ?? "exit node"
        }
        if s.exitNode == nil, let peers = j["Peer"] as? [String: [String: Any]] {
            let opt = peers.values.first { ($0["ExitNodeOption"] as? Bool) == true && ($0["Online"] as? Bool) == true }
            s.exitOption = opt?["HostName"] as? String
            s.exitOptionIP = (opt?["TailscaleIPs"] as? [String])?.first
        }
        return s
    }

    /// Turn Tailscale on. Returns an error message, or nil on success.
    static func enable() -> String? {
        let up = run(["up"], timeout: 20)
        return up.ok ? nil : up.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func useExitNode(_ ip: String) -> String? {
        let r = run(["set", "--exit-node=\(ip)"])
        return r.ok ? nil : r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
