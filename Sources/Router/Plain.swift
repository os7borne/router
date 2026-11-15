import SwiftUI

/// Plain-language layer: turns dBm / SNR / Mbps into words people understand.
enum Quality: Int {
    case none, poor, fair, good, excellent
    var word: String { ["—", "Poor", "Fair", "Good", "Excellent"][rawValue] }
    var color: Color { [Color.secondary, Theme.bad, Theme.warn, Theme.good, Theme.good][rawValue] }
}

struct Activity: Identifiable {
    var id: String { name }
    let name: String
    let symbol: String
    let level: Int // 0 no, 1 maybe, 2 good
}

extension WiFiManager {
    static func quality(rssi: Int, snr: Int? = nil) -> Quality {
        var q = rssi > -55 ? 4 : rssi > -67 ? 3 : rssi > -75 ? 2 : 1
        if let s = snr, s < 15 { q -= 1 }
        return Quality(rawValue: max(1, q))!
    }
    var quality: Quality { ssid == nil ? .none : Self.quality(rssi: rssi, snr: snr) }

    var avgLatency: Double? {
        let l = samples.suffix(15).compactMap(\.latency)
        return l.isEmpty ? nil : l.reduce(0, +) / Double(l.count)
    }

    var interference: (word: String, color: Color) {
        snr >= 25 ? ("Low", Theme.good) : snr >= 15 ? ("Some", Theme.warn) : ("High", Theme.bad)
    }
    var speedWord: (word: String, color: Color) {
        txRate >= 600 ? ("Very fast", Theme.good) : txRate >= 200 ? ("Fast", Theme.good)
            : txRate >= 80 ? ("OK", Theme.warn) : ("Slow", Theme.bad)
    }

    var online: Bool { status != .loginRequired && status != .noInternet && ssid != nil }

    var activities: [Activity] {
        let q = quality.rawValue, lat = avgLatency ?? 0, rate = txRate
        func lvl(_ good: Bool, _ maybe: Bool) -> Int { !online ? 0 : good ? 2 : maybe ? 1 : 0 }
        return [
            Activity(name: "Calls", symbol: "video.fill", level: lvl(q >= 3 && lat < 100, q >= 2)),
            Activity(name: "Streaming", symbol: "play.rectangle.fill", level: lvl(q >= 3 && rate >= 150, q >= 2)),
            Activity(name: "Gaming", symbol: "gamecontroller.fill", level: lvl(q >= 3 && lat < 50, q >= 2 && lat < 100)),
            Activity(name: "Downloads", symbol: "arrow.down.circle.fill", level: lvl(q >= 3 && rate >= 300, q >= 2)),
        ]
    }

    var headline: (text: String, color: Color) {
        switch status {
        case .off: return ("Wi-Fi is turned off", .secondary)
        case .disconnected: return ("Not connected", .secondary)
        case .loginRequired: return ("Sign in to get online", Theme.warn)
        case .noInternet: return ("Connected, but no internet", Theme.bad)
        case .hotspot: return ("Phone hotspot · \(quality.word.lowercased()) signal", quality.color)
        default: return ("\(quality.word) connection", quality.color)
        }
    }

    var advice: String {
        switch status {
        case .loginRequired: return "This is a public network. Sign in on its login page to use the internet."
        case .noInternet: return "Your Mac is linked to the router, but nothing is getting through. Try Diagnose."
        case .hotspot: return "You're using your phone's data. Heavy downloads may use up your plan."
        default:
            switch quality {
            case .excellent: return "Everything should run smoothly."
            case .good: return "Fine for most things."
            case .fair: return "Fine for browsing. Video calls may stutter."
            case .poor: return "Move closer to the router, or switch to a stronger network."
            case .none: return ""
            }
        }
    }

    /// A saved network with clearly better signal than the current one.
    var betterOption: Net? {
        guard ssid != nil, quality.rawValue < 4 else { return nil }
        return networks.filter { $0.known && $0.ssid != ssid && $0.rssi > rssi + 8 }.max { $0.rssi < $1.rssi }
    }

    /// Drops/instability from the live samples.
    var stability: (text: String, color: Color)? {
        let s = samples
        guard s.count >= 8 else { return nil }
        let lost = s.filter { $0.latency == nil }.count
        if lost == 0 { return ("Stable — no drops in the last \(max(1, s.count * 4 / 60)) min", Theme.good) }
        return ("Dropped out \(lost) time\(lost == 1 ? "" : "s") recently", lost > 3 ? Theme.bad : Theme.warn)
    }

    static func speedVerdict(_ mbps: Double) -> String {
        mbps < 10 ? "Slow — basic browsing only"
            : mbps < 50 ? "Okay — HD video and calls"
            : mbps < 200 ? "Fast — 4K streaming and big downloads"
            : "Very fast — handles anything"
    }

    static func bandHint(_ band: String) -> String {
        switch band {
        case "2.4 GHz": return "longer range"
        case "5 GHz": return "faster"
        case "6 GHz": return "fastest"
        default: return ""
        }
    }
}
