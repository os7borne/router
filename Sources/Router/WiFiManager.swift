import CoreWLAN
import CoreLocation
import SwiftUI
import UserNotifications
import ServiceManagement
import os
import Security

/// Passwords the user typed into Router, kept in the login Keychain (macOS's own saved passwords can't be read).
enum SavedPasswords {
    private static let service = "local.router.wifi"
    private static func query(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: ssid]
    }
    static func get(_ ssid: String) -> String? {
        var q = query(ssid); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ ssid: String, _ pw: String) {
        let data = Data(pw.utf8)
        if SecItemUpdate(query(ssid) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var q = query(ssid); q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
    }
    static func remove(_ ssid: String) { SecItemDelete(query(ssid) as CFDictionary) }
}

struct Net: Identifiable, Hashable {
    var id: String { ssid }
    let ssid: String
    let rssi: Int
    let secure: Bool
    let channel: Int
    let band: String
    let known: Bool
    let raw: CWNetwork
    static func == (a: Net, b: Net) -> Bool { a.ssid == b.ssid && a.rssi == b.rssi }
    func hash(into h: inout Hasher) { h.combine(ssid) }
}

struct SpeedResult: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let down: Double
    let up: Double
    let rtt: Double
    let rpm: Int?
    let ssid: String
}

@MainActor
final class WiFiManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WiFiManager()
    let log = Logger(subsystem: "local.router.menubar", category: "wifi")
    let tracker = PlaceTracker()
    private var sampleCount = 0
    private let client = CWWiFiClient.shared()
    private var iface: CWInterface? { client.interface() }
    private let loc = CLLocationManager()
    private var timer: Timer?
    private var lastRoam = Date.distantPast
    private var lastScan = Date.distantPast
    var menuOpen = false
    private var lastReach = Date.distantPast
    private var checkingReach = false
    private var weakFlag = false
    private var prevSSID: String?
    private var started = false

    @Published var powered = true
    @Published var ssid: String?
    @Published var rssi = 0
    @Published var noise = 0
    @Published var txRate = 0.0
    @Published var channelNum = 0
    @Published var bandName = ""
    @Published var networks: [Net] = []
    @Published var aps: [AP] = []
    @Published var scanning = false
    @Published var connecting: String?
    @Published var error: String?
    @Published var needsPassword: String?
    @Published var locationDenied = false
    @Published var locationAllowed = false
    @Published var status: Status = .disconnected
    @Published var reach: Shell.Reach = .unknown
    @Published var gateway: String?
    @Published var samples: [Sample] = []
    @Published var diag: [DiagStep] = []
    @Published var diagVerdict = ""
    @Published var diagRunning = false

    @Published var favorites: [String] = UserDefaults.standard.stringArray(forKey: "favorites") ?? [] {
        didSet { UserDefaults.standard.set(favorites, forKey: "favorites") }
    }
    @Published var smartRoam: Bool = UserDefaults.standard.bool(forKey: "smartRoam") {
        didSet { UserDefaults.standard.set(smartRoam, forKey: "smartRoam") }
    }
    @Published var notify: Bool = UserDefaults.standard.object(forKey: "notify") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notify, forKey: "notify") }
    }

    @Published var showTech: Bool = UserDefaults.standard.bool(forKey: "showTech") {
        didSet { UserDefaults.standard.set(showTech, forKey: "showTech") }
    }
    @Published var sound: Bool = UserDefaults.standard.bool(forKey: "sound") {
        didSet { UserDefaults.standard.set(sound, forKey: "sound") }
    }
    @Published var checkLogin: Bool = UserDefaults.standard.object(forKey: "checkLogin") as? Bool ?? true {
        didSet { UserDefaults.standard.set(checkLogin, forKey: "checkLogin") }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { self.error = error.localizedDescription }
        }
    }

    @Published var memory: [String: SavedNet] = {
        guard let d = UserDefaults.standard.data(forKey: "netMemory"),
              let m = try? JSONDecoder().decode([String: SavedNet].self, from: d) else { return [:] }
        return m
    }() {
        didSet { if let d = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(d, forKey: "netMemory") } }
    }
    @Published var expiryDays: Int = UserDefaults.standard.object(forKey: "expiryDays") as? Int ?? 7 {
        didSet { UserDefaults.standard.set(expiryDays, forKey: "expiryDays") }
    }
    @Published var alsoForgetInMac: Bool = UserDefaults.standard.bool(forKey: "alsoForgetInMac") {
        didSet { UserDefaults.standard.set(alsoForgetInMac, forKey: "alsoForgetInMac") }
    }
    @Published var warnPublic: Bool = UserDefaults.standard.object(forKey: "warnPublic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(warnPublic, forKey: "warnPublic") }
    }
    @Published var mutedPublic: [String] = UserDefaults.standard.stringArray(forKey: "mutedPublic") ?? [] {
        didSet { UserDefaults.standard.set(mutedPublic, forKey: "mutedPublic") }
    }
    @Published var vpn = VPNState()
    /// Networks a scan has found open (no password). Remembered so the public-network warning is right the moment the app starts.
    var openSSIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "openSSIDs") ?? [])
    @Published var lastScanned: Date?
    private var lastVPNCheck = Date.distantPast
    private var lastPrune = Date.distantPast

    @Published var testing = false
    @Published var history: [SpeedResult] = {
        guard let d = UserDefaults.standard.data(forKey: "history"),
              let h = try? JSONDecoder().decode([SpeedResult].self, from: d) else { return [] }
        return h
    }()

    override init() {
        super.init()
        loc.delegate = self
        loc.requestWhenInUseAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        updateAuth()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { await scan() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.updateAuth(); self.refresh() }
    }
    private func updateAuth() {
        let s = loc.authorizationStatus
        locationDenied = (s == .denied || s == .restricted)
        locationAllowed = (s == .authorizedAlways)
    }

    var locationUndetermined: Bool { loc.authorizationStatus == .notDetermined }

    /// Ask for Location access, or send the user to the right System Settings page if it was already decided.
    func requestLocationAccess() {
        if locationUndetermined {
            NSApp.activate(ignoringOtherApps: true)
            loc.requestAlwaysAuthorization()
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        }
    }

    var snr: Int { rssi - noise }
    var isHotspot: Bool {
        if let g = gateway, g.hasPrefix("172.20.10.") || g.hasPrefix("192.168.43.") { return true }
        let s = (ssid ?? "").lowercased()
        return s.contains("iphone") || s.contains("android") || s.contains("hotspot")
    }

    func onOpen() {
        menuOpen = true
        refresh()
        lastReach = .distantPast
        Task { await scan() }
        tick()
    }

    func refresh() {
        guard let i = iface else { return }
        powered = i.powerOn()
        ssid = i.ssid()
        rssi = i.rssiValue()
        noise = i.noiseMeasurement()
        txRate = i.transmitRate()
        if let c = i.wlanChannel() { channelNum = c.channelNumber; bandName = Self.band(c) }
        else { channelNum = 0; bandName = "" }
        if ssid != prevSSID { prevSSID = ssid; reach = .unknown; gateway = nil; lastReach = .distantPast; weakFlag = false }
        recompute()
    }

    private static func band(_ c: CWChannel) -> String {
        switch c.channelBand {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return "?"
        }
    }
    private static func width(_ c: CWChannel) -> String {
        switch c.channelWidth {
        case .width20MHz: return "20"
        case .width40MHz: return "40"
        case .width80MHz: return "80"
        case .width160MHz: return "160"
        default: return ""
        }
    }

    // MARK: periodic work
    private func tick() {
        refresh()
        tracker.tick(ssid: ssid, hotspot: isHotspot, connected: powered && ssid != nil)
        guard powered else { return }
        if ssid != nil {
            // weak-signal hysteresis
            if rssi < -75 { weakFlag = true } else if rssi > -68 { weakFlag = false }
            Task {
                let l = await Task.detached { Shell.latencyOnce() }.value
                samples.append(Sample(t: Date(), rssi: rssi, latency: l))
                if samples.count > 90 { samples.removeFirst(samples.count - 90) }
                sampleCount += 1
                if sampleCount % 15 == 0, let l { tracker.recordSample(kind: "live", rtt: l, rssi: rssi) }
            }
            if Date().timeIntervalSince(lastReach) > 15 && !checkingReach { Task { await checkReach() } }
        }
        recompute()
        if let s = ssid, powered { touchMemory(s) }
        if Date().timeIntervalSince(lastPrune) > 3600 { lastPrune = Date(); pruneMemory() }
        if Date().timeIntervalSince(lastVPNCheck) > (menuOpen ? 10 : 60), Tailscale.installed {
            lastVPNCheck = Date()
            Task { let v = await Task.detached { Tailscale.state() }.value; if v != vpn { vpn = v } }
        }
        // Keep the network list fresh: often while the menu is open, occasionally otherwise (feeds smart roam).
        if powered, !scanning, connecting == nil, Date().timeIntervalSince(lastScan) > (menuOpen ? 15 : 60) {
            Task { await scan() }
        }
        guard smartRoam, !scanning, connecting == nil, !testing,
              Date().timeIntervalSince(lastRoam) > 60 else { return }
        if ssid == nil || rssi < -75 { Task { await roam() } }
    }

    func checkReach() async {
        checkingReach = true; defer { checkingReach = false }
        gateway = await Task.detached { Shell.gateway() }.value
        var r = await Task.detached { Shell.captive() }.value
        if r == .login && !checkLogin { r = .ok }
        reach = r
        lastReach = Date()
        recompute()
    }

    func openLogin() { PortalController.shared.open(wifi: self) }
    func recheckReach() { if !checkingReach { Task { await checkReach() } } }

    func enableVPN() {
        Task {
            let err = await Task.detached { Tailscale.enable() }.value
            if let err, !err.isEmpty { error = "Couldn't turn on Tailscale: \(err)" }
            vpn = await Task.detached { Tailscale.state() }.value
        }
    }
    func useExitNode(_ ip: String) {
        Task {
            let err = await Task.detached { Tailscale.useExitNode(ip) }.value
            if let err, !err.isEmpty { error = "Couldn't use the exit node: \(err)" }
            vpn = await Task.detached { Tailscale.state() }.value
        }
    }
    func muteWarning(_ s: String) { if !mutedPublic.contains(s) { mutedPublic.append(s) } }

    private var lastStatus: Status?
    private func recompute() {
        let s: Status
        if !powered { s = .off }
        else if ssid == nil { s = .disconnected }
        else if reach == .login { s = .loginRequired }
        else if reach == .offline { s = .noInternet }
        else if weakFlag { s = .weak }
        else if isHotspot { s = .hotspot }
        else { s = .connected }
        guard s != status else { return }
        let first = lastStatus == nil
        lastStatus = status
        status = s
        if !first { notifyChange(s) }
    }

    private func notifyChange(_ s: Status) {
        guard notify else { return }
        let n = ssid ?? "network"
        let (title, body): (String, String)
        switch s {
        case .off: (title, body) = ("Wi-Fi off", "Wi-Fi was turned off.")
        case .disconnected: (title, body) = ("Wi-Fi disconnected", "Not connected to any network.")
        case .connected: (title, body) = ("Connected", "Connected to \(n) (\(rssi) dBm).")
        case .hotspot: (title, body) = ("Hotspot connected", "Connected to personal hotspot \(n).")
        case .weak: (title, body) = ("Weak signal", "\(n) is at \(rssi) dBm. Move closer or switch network.")
        case .loginRequired: (title, body) = ("Login required", "\(n) needs you to sign in. Open Router and press Sign in.")
        case .noInternet: (title, body) = ("No internet", "Connected to \(n) but the internet is unreachable.")
        }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        if sound { c.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func roam() async {
        lastRoam = Date()
        await scan()
        let current = rssi
        let candidates = networks.filter { favorites.contains($0.ssid) && $0.ssid != ssid && $0.known }
        if let best = candidates.max(by: { $0.rssi < $1.rssi }),
           ssid == nil || best.rssi > current + 10 {
            await connect(best, password: nil)
        }
    }

    // MARK: scan / connect
    func scan() async {
        guard let i = iface, powered, !scanning else { return }
        scanning = true
        lastScan = Date()
        defer { scanning = false }
        let known = Set(i.configuration()?.networkProfiles.compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? [])
        let found: [CWNetwork] = await Task.detached {
            (try? i.scanForNetworks(withSSID: nil)).map(Array.init) ?? []
        }.value

        lastScanned = Date()
        defer {
            let open = Set(networks.filter { !$0.secure }.map(\.ssid))
            if !networks.isEmpty, open != openSSIDs { openSSIDs = open; UserDefaults.standard.set(Array(open), forKey: "openSSIDs") }
        }
        aps = found.enumerated().map { idx, n in
            AP(id: n.bssid ?? "\(idx)-\(n.ssid ?? "")-\(n.wlanChannel?.channelNumber ?? 0)",
               ssid: (n.ssid?.isEmpty == false ? n.ssid! : "Hidden network"),
               rssi: n.rssiValue, channel: n.wlanChannel?.channelNumber ?? 0,
               band: n.wlanChannel.map(Self.band) ?? "?", width: n.wlanChannel.map(Self.width) ?? "",
               secure: !n.supportsSecurity(.none))
        }.sorted { $0.rssi > $1.rssi }

        var best: [String: CWNetwork] = [:]
        for n in found {
            guard let s = n.ssid, !s.isEmpty else { continue }
            if let o = best[s], o.rssiValue >= n.rssiValue { continue }
            best[s] = n
        }
        networks = best.map { s, n in
            Net(ssid: s, rssi: n.rssiValue, secure: !n.supportsSecurity(.none),
                channel: n.wlanChannel?.channelNumber ?? 0,
                band: n.wlanChannel.map(Self.band) ?? "", known: known.contains(s), raw: n)
        }.sorted {
            if $0.ssid == ssid { return true }
            if $1.ssid == ssid { return false }
            let f0 = favorites.contains($0.ssid), f1 = favorites.contains($1.ssid)
            if f0 != f1 { return f0 }
            return $0.rssi > $1.rssi
        }
    }

    /// Connected network first, then favourites, then strongest signal. Computed so it stays right as state changes between scans.
    var sortedNetworks: [Net] {
        networks.sorted {
            let c0 = $0.ssid == ssid, c1 = $1.ssid == ssid
            if c0 != c1 { return c0 }
            let f0 = favorites.contains($0.ssid), f1 = favorites.contains($1.ssid)
            if f0 != f1 { return f0 }
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.ssid < $1.ssid
        }
    }

    func connect(_ n: Net, password: String?) async {
        guard let i = iface else { return }
        connecting = n.ssid; error = nil; needsPassword = nil
        defer { connecting = nil; refresh() }
        let ssid = n.ssid
        // Re-scan for this exact network: a saved scan result goes stale (hotspots especially).
        let fresh: CWNetwork? = await Task.detached {
            (try? i.scanForNetworks(withSSID: Data(ssid.utf8)))?.max { $0.rssiValue < $1.rssiValue }
        }.value
        guard let target = fresh else {
            log.error("connect \(ssid, privacy: .public): not visible in scan")
            error = "Can't see “\(ssid)” right now. Is it in range, and is the hotspot or router on?"
            return
        }
        let result: (code: Int, text: String)? = await Task.detached {
            do { try i.associate(to: target, password: password); return nil }
            catch let e as NSError { return (e.code, e.localizedDescription) }
        }.value
        guard let r = result else {
            log.info("connect \(ssid, privacy: .public): ok")
            if let password, !password.isEmpty { SavedPasswords.set(ssid, password) }
            return
        }
        // macOS couldn't join on its own: retry once with the password Router saved earlier.
        if password == nil, !target.supportsSecurity(.none), let saved = SavedPasswords.get(ssid) {
            await connect(n, password: saved)
            return
        }
        if password != nil { SavedPasswords.remove(ssid) }
        log.error("connect \(ssid, privacy: .public): failed code \(r.code) \(r.text, privacy: .public)")
        if target.supportsSecurity(.none) {
            error = "Couldn't join “\(ssid)” (error \(r.code))."
        } else if password == nil {
            // macOS wouldn't join with its saved password — ask for it instead of failing silently.
            needsPassword = ssid
            error = "macOS couldn't use the saved password for “\(ssid)”. Enter it to join."
        } else {
            error = "Couldn't join “\(ssid)”. The password may be wrong (error \(r.code))."
            needsPassword = ssid
        }
    }

    func disconnect() { iface?.disassociate(); refresh() }

    func setPower(_ on: Bool) {
        do { try iface?.setPower(on) } catch { self.error = error.localizedDescription }
        refresh()
        if on { Task { try? await Task.sleep(nanoseconds: 2_000_000_000); await scan() } }
        else { networks = []; aps = []; samples = [] }
    }

    func toggleFavorite(_ s: String) {
        if let idx = favorites.firstIndex(of: s) { favorites.remove(at: idx) } else { favorites.append(s) }
    }

    func forget(_ s: String, keepRouterData: Bool = false) {
        if !keepRouterData { removeNetwork(s) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-removepreferredwirelessnetwork", iface?.interfaceName ?? "en0", s]
        try? p.run()
    }

    // MARK: channel analysis
    func channelLoads(band: String) -> (loads: [ChanLoad], recommended: Int?) {
        let list = aps.filter { $0.band == band }
        let candidates: [Int]
        switch band {
        case "2.4 GHz": candidates = Array(1...11)
        case "5 GHz": candidates = Array(Set([36, 40, 44, 48, 149, 153, 157, 161] + list.map(\.channel))).sorted()
        default: candidates = Array(Set(list.map(\.channel))).sorted()
        }
        func load(_ c: Int) -> Double {
            list.reduce(0) { acc, ap in
                let s = Double(max(0, ap.rssi + 100)) / 60
                if band == "2.4 GHz" {
                    let d = abs(ap.channel - c)
                    return d <= 4 ? acc + s * (1 - Double(d) / 5) : acc
                }
                return ap.channel == c ? acc + s : acc
            }
        }
        let rec: Int? = (band == "2.4 GHz" ? [1, 6, 11] : candidates.filter { [36, 40, 44, 48, 149, 153, 157, 161].contains($0) || band == "6 GHz" })
            .min { load($0) < load($1) }
        let loads = candidates.map { c in
            ChanLoad(ch: c, load: load(c), kind: (c == channelNum && band == bandName) ? 1 : (c == rec ? 2 : 0))
        }
        return (loads, rec)
    }
    var bandsPresent: [String] { ["2.4 GHz", "5 GHz", "6 GHz"].filter { b in aps.contains { $0.band == b } } }

    // MARK: diagnostics
    func runDiagnostics() {
        guard !diagRunning else { return }
        diagRunning = true; diagVerdict = ""
        let ids = ["Wi-Fi link", "Router (gateway)", "DNS", "Internet (1.1.1.1)", "Web / login"]
        diag = ids.map { DiagStep(id: $0) }
        func set(_ i: Int, _ st: DiagStep.State, _ d: String) { diag[i].state = st; diag[i].detail = d }
        Task {
            refresh()
            var failed: String?
            // 0 link
            set(0, .running, "")
            if ssid == nil { set(0, .fail, "Not connected"); failed = "You're not connected to Wi-Fi." }
            else if rssi < -75 || snr < 15 { set(0, .warn, "\(rssi) dBm, SNR \(snr) dB (weak)"); failed = "Wi-Fi signal is weak — move closer or use 5 GHz." }
            else { set(0, .ok, "\(rssi) dBm, SNR \(snr) dB, \(Int(txRate)) Mbps") }
            if ssid != nil {
                // 1 gateway
                set(1, .running, "")
                let gw = await Task.detached { Shell.gateway() }.value
                gateway = gw
                if let gw {
                    let p = await Task.detached { Shell.ping(gw, count: 4) }.value
                    if p.loss >= 100 { set(1, .fail, "\(gw): no reply"); failed = failed ?? "Your router isn't answering — reboot it or reconnect." }
                    else if p.loss > 0 || (p.avg ?? 0) > 50 { set(1, .warn, "\(gw): \(String(format: "%.0f", p.avg ?? 0)) ms, \(Int(p.loss))% loss"); failed = failed ?? "Unstable link to router (packet loss / high latency)." }
                    else { set(1, .ok, "\(gw): \(String(format: "%.1f", p.avg ?? 0)) ms") }
                } else { set(1, .fail, "No gateway"); failed = failed ?? "No default route — DHCP may have failed." }
                // 2 DNS
                set(2, .running, "")
                let d = await Task.detached { Shell.dns("apple.com") }.value
                if let d { set(2, d > 300 ? .warn : .ok, String(format: "%.0f ms", d)); if d > 300 { failed = failed ?? "DNS is slow — try a different DNS server." } }
                else { set(2, .fail, "Lookup failed"); failed = failed ?? "DNS lookup failed — router DNS is broken or no internet." }
                // 3 internet
                set(3, .running, "")
                let p = await Task.detached { Shell.ping("1.1.1.1", count: 4) }.value
                if p.loss >= 100 { set(3, .fail, "No reply"); failed = failed ?? "Router is fine but the internet is unreachable — ISP or modem issue." }
                else if p.loss > 0 || (p.avg ?? 0) > 150 { set(3, .warn, "\(String(format: "%.0f", p.avg ?? 0)) ms, \(Int(p.loss))% loss"); failed = failed ?? "Internet connection is lossy or slow." }
                else { set(3, .ok, String(format: "%.0f ms", p.avg ?? 0)) }
                // 4 captive
                set(4, .running, "")
                let r = await Task.detached { Shell.captive() }.value
                reach = r; lastReach = Date(); recompute()
                switch r {
                case .ok: set(4, .ok, "Open internet")
                case .login: set(4, .fail, "Login page intercepting"); failed = "This network needs a login — press Sign in."
                default: set(4, .fail, "HTTP failed"); failed = failed ?? "Web requests are failing."
                }
            }
            diagVerdict = failed ?? "Everything looks healthy."
            diagRunning = false
        }
    }

    // MARK: speed test
    func runSpeedTest() {
        guard !testing else { return }
        testing = true; error = nil
        let name = ssid ?? "—"
        Task {
            let out: Data? = await Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
                p.arguments = ["-c"]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
                do { try p.run() } catch { return nil }
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                return d
            }.value
            testing = false
            guard let out, let j = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
                  let dl = j["dl_throughput"] as? Double, let ul = j["ul_throughput"] as? Double else {
                error = "Speed test failed"; return
            }
            let rtt = (j["base_rtt"] as? Double) ?? 0
            let rpm = (j["responsiveness"] as? Double).map { Int($0) }
            history.insert(.init(date: Date(), down: dl / 1e6, up: ul / 1e6, rtt: rtt, rpm: rpm, ssid: name), at: 0)
            tracker.recordSample(kind: "speed", down: dl / 1e6, up: ul / 1e6, rtt: rtt, rssi: rssi)
            history = Array(history.prefix(10))
            if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: "history") }
        }
    }
}
