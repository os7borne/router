import Foundation
import Security

/// One network Router has seen you join. `saved` networks are kept until you remove them;
/// the rest are forgotten after `expiryDays` without joining.
struct SavedNet: Codable {
    var ssid: String
    var saved: Bool
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
    func isSaved(_ ssid: String) -> Bool { memory[ssid]?.saved ?? false }

    func setSaved(_ ssid: String, _ saved: Bool) {
        var m = memory[ssid] ?? SavedNet(ssid: ssid, saved: saved, lastJoined: Date())
        m.saved = saved
        memory[ssid] = m
    }

    func toggleSaved(_ ssid: String) { setSaved(ssid, !isSaved(ssid)) }

    /// Days until an unsaved network is forgotten, or nil if it's saved / unknown to Router.
    func daysLeft(_ ssid: String) -> Int? {
        guard let m = memory[ssid], !m.saved else { return nil }
        let used = Date().timeIntervalSince(m.lastJoined) / 86_400
        return max(0, Int((Double(expiryDays) - used).rounded(.up)))
    }

    /// Record that we're on this network right now (resets its expiry clock).
    func touchMemory(_ ssid: String) {
        var m = memory[ssid] ?? SavedNet(ssid: ssid, saved: false, lastJoined: Date())
        // Update at most once a minute so we don't rewrite defaults on every tick.
        guard memory[ssid] == nil || Date().timeIntervalSince(m.lastJoined) > 60 else { return }
        m.lastJoined = Date()
        memory[ssid] = m
    }

    /// Delete Router-held data for unsaved networks that have gone unused too long.
    func pruneMemory() {
        let cutoff = Date().addingTimeInterval(-Double(expiryDays) * 86_400)
        for (ssid, m) in memory where !m.saved && m.lastJoined < cutoff && ssid != self.ssid {
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

    var savedNetworks: [SavedNet] { memory.values.filter(\.saved).sorted { $0.ssid < $1.ssid } }
    var unsavedNetworks: [SavedNet] { memory.values.filter { !$0.saved }.sorted { $0.lastJoined > $1.lastJoined } }

    /// An open network, or one behind a sign-in page, that isn't a personal hotspot.
    var onPublicNetwork: Bool {
        guard let s = ssid, !isHotspot else { return false }
        if status == .loginRequired { return true }
        if let n = networks.first(where: { $0.ssid == s }) { return !n.secure }
        return openSSIDs.contains(s)   // before the first scan finishes, use what the last scan found
    }
}
