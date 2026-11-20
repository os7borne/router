import Foundation
import Security

/// One network Router has seen you join. Every network is remembered; one is forgotten after
/// `expiryDays` without joining (starred networks are never forgotten). `saved` is a leftover from
/// the old manual Save button; it's only read so older data still loads.
struct SavedNet: Codable {
    var ssid: String
    var saved: Bool = false
    var lastJoined: Date
}

/// Details typed into a sign-in page, kept per network in the Keychain.
struct PortalProfile: Codable {
    var host: String
    var fields: [String: String]
}

enum PortalStore {
    private static let service = "local.router.portal"
    private static func query(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: ssid]
    }
    static func get(_ ssid: String) -> PortalProfile? {
        var q = query(ssid); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(PortalProfile.self, from: d)
    }
    static func set(_ ssid: String, _ p: PortalProfile) {
        guard let data = try? JSONEncoder().encode(p) else { return }
        if SecItemUpdate(query(ssid) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var q = query(ssid); q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
    }
    static func remove(_ ssid: String) { SecItemDelete(query(ssid) as CFDictionary) }
}

extension WiFiManager {
    /// Days until a network is forgotten, or nil if it's starred or unknown to Router.
    func daysLeft(_ ssid: String) -> Int? {
        guard let m = memory[ssid], !favorites.contains(ssid) else { return nil }
        let used = Date().timeIntervalSince(m.lastJoined) / 86_400
        return max(0, Int((Double(expiryDays) - used).rounded(.up)))
    }

    /// Record that we're on this network right now (resets its expiry clock).
    func touchMemory(_ ssid: String) {
        var m = memory[ssid] ?? SavedNet(ssid: ssid, lastJoined: Date())
        // Update at most once a minute so we don't rewrite defaults on every tick.
        guard memory[ssid] == nil || Date().timeIntervalSince(m.lastJoined) > 60 else { return }
        m.lastJoined = Date()
        memory[ssid] = m
    }

    /// Delete Router-held data for networks that have gone unused too long. Starred networks are kept.
    /// Waits until we're on a network, so a long gap with Router closed can't expire everything at launch.
    func pruneMemory() {
        guard ssid != nil else { return }
        let cutoff = Date().addingTimeInterval(-Double(expiryDays) * 86_400)
        for (ssid, m) in memory where m.lastJoined < cutoff && ssid != self.ssid && !favorites.contains(ssid) {
            SavedPasswords.remove(ssid)
            PortalStore.remove(ssid)
            if alsoForgetInMac { forget(ssid, keepRouterData: true) }
            memory[ssid] = nil
        }
    }

    /// Forget a network completely (Router's copy and, if asked, macOS's).
    func removeNetwork(_ ssid: String) {
        SavedPasswords.remove(ssid)
        PortalStore.remove(ssid)
        memory[ssid] = nil
    }

    var rememberedNetworks: [SavedNet] { memory.values.sorted { $0.lastJoined > $1.lastJoined } }

    /// An open network, or one behind a sign-in page, that isn't a personal hotspot.
    var onPublicNetwork: Bool {
        guard let s = ssid, !isHotspot else { return false }
        if status == .loginRequired { return true }
        if let n = networks.first(where: { $0.ssid == s }) { return !n.secure }
        return openSSIDs.contains(s)   // before the first scan finishes, use what the last scan found
    }
}
