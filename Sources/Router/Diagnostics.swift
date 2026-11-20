import Foundation
import Darwin

enum Shell {
    static func run(_ path: String, _ args: [String]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
    }

    static func gateway() -> String? {
        let o = run("/sbin/route", ["-n", "get", "default"]).out
        for l in o.split(separator: "\n") where l.contains("gateway:") {
            return l.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    /// returns (loss %, avg ms)
    static func ping(_ host: String, count: Int) -> (loss: Double, avg: Double?) {
        let o = run("/sbin/ping", ["-c", "\(count)", "-W", "1000", "-q", host]).out
        var loss = 100.0, avg: Double?
        for l in o.split(separator: "\n") {
            if l.contains("packet loss"), let r = l.range(of: #"[\d.]+(?=% packet loss)"#, options: .regularExpression) {
                loss = Double(l[r]) ?? 100
            }
            if l.contains("min/avg/max") {
                let parts = l.split(separator: "=").last?.split(separator: "/")
                if let p = parts, p.count > 1 { avg = Double(p[1].trimmingCharacters(in: .whitespaces)) }
            }
        }
        return (loss, avg)
    }

    static func dns(_ host: String) -> Double? {
        let t = Date()
        var res: UnsafeMutablePointer<addrinfo>?
        var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM
        let r = getaddrinfo(host, nil, &hints, &res)
        if res != nil { freeaddrinfo(res) }
        return r == 0 ? Date().timeIntervalSince(t) * 1000 : nil
    }

    enum Reach { case unknown, ok, login, offline }
    static func captive() -> (reach: Reach, url: URL?) {
        // No -L: a portal's redirect target is what the sign-in window should load directly.
        let r = run("/usr/bin/curl", ["-s", "--connect-timeout", "2", "-m", "4", "-w", "\n__REDIR__%{redirect_url}",
                                      "http://captive.apple.com/hotspot-detect.html"])
        if r.code != 0 { return (.offline, nil) }
        let parts = r.out.components(separatedBy: "\n__REDIR__")
        if parts[0].contains("Success") { return (.ok, nil) }
        let loc = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (.login, loc.isEmpty ? nil : URL(string: loc))
    }

    static func latencyOnce() -> Double? {
        let o = run("/sbin/ping", ["-c", "1", "-W", "1000", "1.1.1.1"]).out
        guard let r = o.range(of: #"time=[\d.]+"#, options: .regularExpression) else { return nil }
        return Double(o[r].dropFirst(5))
    }
}

struct DiagStep: Identifiable {
    enum State { case pending, running, ok, warn, fail }
    let id: String
    var state: State = .pending
    var detail = ""
}

struct Sample: Identifiable {
    let id = UUID()
    let t: Date
    let rssi: Int
    let latency: Double?
}

struct AP: Identifiable {
    let id: String
    let ssid: String
    let rssi: Int
    let channel: Int
    let band: String
    let width: String
    let secure: Bool
}

struct ChanLoad: Identifiable {
    var id: Int { ch }
    let ch: Int
    let load: Double
    let kind: Int // 0 other, 1 current, 2 recommended
}

enum Status: String {
    case off, disconnected, connected, hotspot, weak, loginRequired, noInternet
}
