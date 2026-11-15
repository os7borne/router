import Foundation
import CoreLocation
import AppKit

enum Period: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year", all = "All"
    static let simple: [Period] = [.day, .week, .month, .year]
    var id: String { rawValue }
    var component: Calendar.Component { switch self { case .day: return .day; case .week: return .weekOfYear; case .month: return .month; case .year, .all: return .year } }
    var bucket: Calendar.Component { switch self { case .day: return .hour; case .week, .month: return .day; case .year, .all: return .month } }
}
struct ChartPoint: Identifiable { let id = UUID(); let start: Date; let series: String; let hours: Double }
struct Total: Identifiable { let id: String; let name: String; let sub: String?; let seconds: TimeInterval; let placeId: Int64? }
struct Report { var from = Date(); var to = Date(); var bucket: Calendar.Component = .day; var label = ""; var total: TimeInterval = 0; var points: [ChartPoint] = []; var names: [String] = []; var rows: [Total] = [] }
struct PlaceRowData: Identifiable {
    let id: Int64; let name: String; let city: String
    let seconds: TimeInterval; let share: Double; let visits: Int
    let avgStay: TimeInterval; let longest: TimeInterval; let lastSeen: Date
    let avgDown: Double?; let avgRssi: Int?; let avgRTT: Double?; let slowestHour: Int?
}
struct LogRow: Identifiable { let id: Int64; let start: Date; let duration: TimeInterval; let place: String; let network: String }
struct PlaceStats {
    var total: TimeInterval = 0, visits = 0, tests = 0
    var avgDown: Double?, avgUp: Double?, avgRTT: Double?, avgRssi: Int?
    var slowestHour: Int?
}

func fmtDuration(_ s: TimeInterval) -> String {
    let m = Int(s / 60), h = m / 60
    if s < 60 { return s < 1 ? "0m" : "<1m" }
    if h >= 100 { return "\(h)h" }
    return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
}

@MainActor
final class PlaceTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    let store = Store()
    @Published var places: [Int64: Place] = [:]
    @Published var currentPlaceId: Int64?
    @Published var revision = 0
    @Published var focusPlace: Int64?
    @Published var paused: Bool = UserDefaults.standard.bool(forKey: "trackPaused") {
        didSet { UserDefaults.standard.set(paused, forKey: "trackPaused"); if paused { endSession() } }
    }
    @Published var radius: Double = UserDefaults.standard.object(forKey: "placeRadius") as? Double ?? 150 {
        didSet { UserDefaults.standard.set(radius, forKey: "placeRadius") }
    }

    private let lm = CLLocationManager()
    private var session: Int64?
    private var sessionSSID: String?
    private var sessionHotspot = false
    private var lastBeat = Date.distantPast
    private var lastLoc: CLLocation?
    private var lastLocReq = Date.distantPast
    private var lastGeocode = Date.distantPast
    private var geocoding = false

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        for p in store.allPlaces() { places[p.id] = p }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSession() }
        }
    }

    var locationDenied: Bool { lm.authorizationStatus == .denied || lm.authorizationStatus == .restricted }

    // MARK: driven by WiFiManager every ~4s
    func tick(ssid: String?, hotspot: Bool, connected: Bool) {
        guard !paused, connected, let ssid else { endSession(); return }
        let now = Date()
        if session != nil, sessionSSID != ssid || now.timeIntervalSince(lastBeat) > 45 { endSession() }
        if session == nil { openSession(ssid: ssid, hotspot: hotspot, place: nil, now: now) }
        else if let s = session { store.heartbeat(s, now); lastBeat = now }
        if now.timeIntervalSince(lastLocReq) > 600 { requestLocation() }
        if now.timeIntervalSince(lastGeocode) > 30 { geocodeNext() }
        revision += 1
    }

    private func openSession(ssid: String, hotspot: Bool, place: Int64?, now: Date) {
        session = store.startSession(placeId: place, ssid: ssid, at: now)
        sessionSSID = ssid; sessionHotspot = hotspot; lastBeat = now
        currentPlaceId = place
        if place == nil {
            if let l = lastLoc, now.timeIntervalSince(l.timestamp) < 600 { assign(loc: l) }
            else if locationDenied { assign(loc: nil) }
            else { requestLocation() }
        }
    }

    func endSession() {
        guard session != nil else { return }
        session = nil; sessionSSID = nil; currentPlaceId = nil; revision += 1
    }

    private func requestLocation() { lastLocReq = Date(); lm.requestLocation() }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        Task { @MainActor in self.gotLocation(l) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.session != nil && self.currentPlaceId == nil { self.assign(loc: self.lastLoc) } }
    }

    private func gotLocation(_ l: CLLocation) {
        lastLoc = l
        guard session != nil, let ssid = sessionSSID else { return }
        if currentPlaceId == nil { assign(loc: l); return }
        let target = findOrCreate(ssid: sessionHotspot ? nil : ssid, loc: l)
        if target != currentPlaceId {     // moved to a different place on the same network
            let hot = sessionHotspot
            endSession()
            openSession(ssid: ssid, hotspot: hot, place: target, now: Date())
        }
    }

    private func assign(loc: CLLocation?) {
        guard let s = session, let ssid = sessionSSID else { return }
        let id = findOrCreate(ssid: sessionHotspot ? nil : ssid, loc: loc)
        store.setSessionPlace(s, id)
        currentPlaceId = id; revision += 1
    }

    // MARK: place matching
    private func findOrCreate(ssid: String?, loc: CLLocation?) -> Int64 {
        let r = radius
        // 1. same spot (any network), nearest wins
        if let loc {
            var best: Place?; var bd = Double.infinity
            for p in places.values {
                guard let la = p.lat, let lo = p.lon else { continue }
                let d = loc.distance(from: CLLocation(latitude: la, longitude: lo))
                if d <= r, d < bd { best = p; bd = d }
            }
            if let b = best { return b.id }
        }
        // 2. same network name nearby (e.g. one office, many access points), or no coordinates to compare
        if let ssid {
            for p in places.values where p.ssid == ssid {
                if let loc, let la = p.lat, let lo = p.lon {
                    if loc.distance(from: CLLocation(latitude: la, longitude: lo)) <= max(2 * r, 300) { return p.id }
                } else {
                    if loc != nil, p.lat == nil { var q = p; q.lat = loc?.coordinate.latitude; q.lon = loc?.coordinate.longitude; save(q) }
                    return p.id
                }
            }
        } else if loc == nil, let p = places.values.first(where: { $0.ssid == nil && $0.lat == nil }) { return p.id }
        // 3. new place
        let p = store.insertPlace(ssid: ssid, lat: loc?.coordinate.latitude, lon: loc?.coordinate.longitude)
        places[p.id] = p
        return p.id
    }

    private func save(_ p: Place) { places[p.id] = p; store.update(p); revision += 1 }
    func rename(_ id: Int64, _ name: String) {
        guard var p = places[id] else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        p.name = n.isEmpty ? nil : n; save(p)
    }
    func delete(_ id: Int64) {
        store.deletePlace(id); places[id] = nil
        if currentPlaceId == id { endSession() }
        revision += 1
    }
    func wipeAll() { endSession(); store.wipe(); places = [:]; revision += 1 }

    // MARK: reverse geocoding (Apple; sends coordinates once per place)
    private func geocodeNext() {
        guard !geocoding, let p = places.values.first(where: { $0.lat != nil && $0.city == nil }) else { return }
        geocoding = true; lastGeocode = Date()
        let loc = CLLocation(latitude: p.lat!, longitude: p.lon!)
        Task {
            defer { geocoding = false }
            guard let pm = try? await CLGeocoder().reverseGeocodeLocation(loc).first else { return }
            var q = places[p.id] ?? p
            q.area = pm.subLocality ?? pm.thoroughfare ?? pm.name
            q.city = pm.locality ?? pm.administrativeArea ?? pm.country ?? "Unknown"
            q.country = pm.country
            save(q)
        }
    }

    // MARK: samples
    func recordSample(kind: String, down: Double? = nil, up: Double? = nil, rtt: Double? = nil, rssi: Int? = nil) {
        guard !paused, let p = currentPlaceId else { return }
        store.addSample(place: p, kind: kind, down: down, up: up, rtt: rtt, rssi: rssi)
    }

    // MARK: analytics
    func todayTotal(for id: Int64) -> TimeInterval {
        let cal = Calendar.current, from = cal.startOfDay(for: Date()), now = Date()
        return store.sessions(from: from, to: now).filter { $0.placeId == id }
            .reduce(0) { $0 + max(0, min($1.end, now).timeIntervalSince(max($1.start, from))) }
    }

    func report(period: Period, offset: Int, cities: Bool, topN: Int = 4) -> Report {
        let cal = Calendar.current, now = Date()
        var from: Date, to: Date, bucket = period.bucket
        if period == .all {
            from = store.earliest() ?? cal.startOfDay(for: now); to = now
            let days = to.timeIntervalSince(from) / 86400
            bucket = days <= 60 ? .day : days <= 400 ? .weekOfYear : .month
            from = cal.dateInterval(of: bucket, for: from)?.start ?? from
        } else {
            guard let anchor = cal.date(byAdding: period.component, value: offset, to: now),
                  let iv = cal.dateInterval(of: period.component, for: anchor) else { return Report() }
            from = iv.start; to = iv.end
        }
        var starts: [Date] = []; var d = from
        while d < to { starts.append(d); d = cal.date(byAdding: bucket, value: 1, to: d) ?? to }
        let ends = starts.indices.map { $0 + 1 < starts.count ? starts[$0 + 1] : to }

        func key(_ pid: Int64?) -> (String, String) {
            guard let pid, let p = places[pid] else { return ("?", "Unknown") }
            return cities ? (p.city ?? "Unknown", p.city ?? "Unknown") : ("p\(pid)", p.displayName)
        }
        var names: [String: String] = [:], totals: [String: TimeInterval] = [:], pids: [String: Int64] = [:]
        var perBucket = [[String: TimeInterval]](repeating: [:], count: starts.count)
        for r in store.sessions(from: from, to: min(to, now)) {
            let (k, n) = key(r.placeId); names[k] = n; if let p = r.placeId { pids[k] = p }
            let s = max(r.start, from), e = min(r.end, to, now)
            guard e > s else { continue }
            totals[k, default: 0] += e.timeIntervalSince(s)
            for i in starts.indices {
                let o = min(e, ends[i]).timeIntervalSince(max(s, starts[i]))
                if o > 0 { perBucket[i][k, default: 0] += o }
            }
        }
        let ranked = totals.sorted { $0.value > $1.value }
        let top = Set(ranked.prefix(topN).map(\.key))
        var pts: [ChartPoint] = []
        for (i, b) in perBucket.enumerated() {
            var other = 0.0
            for (k, v) in b { if top.contains(k) { pts.append(.init(start: starts[i], series: names[k] ?? k, hours: v / 3600)) } else { other += v } }
            if other > 0 { pts.append(.init(start: starts[i], series: "Other", hours: other / 3600)) }
        }
        var chartNames = ranked.prefix(topN).map { names[$0.key] ?? $0.key }
        if ranked.count > topN { chartNames.append("Other") }

        let f = DateFormatter()
        let label: String
        switch period {
        case .day: label = offset == 0 ? "Today" : offset == -1 ? "Yesterday" : { f.dateFormat = "EEE d MMM"; return f.string(from: from) }()
        case .week: label = offset == 0 ? "This week" : { f.dateFormat = "d MMM"; return f.string(from: from) + " – " + f.string(from: to.addingTimeInterval(-1)) }()
        case .month: label = { f.dateFormat = "MMMM yyyy"; return f.string(from: from) }()
        case .year: label = { f.dateFormat = "yyyy"; return f.string(from: from) }()
        case .all: label = "All time"
        }
        let rows = ranked.map { (k, v) -> Total in
            let sub: String? = cities ? nil : pids[k].flatMap { places[$0]?.subtitle }
            return Total(id: k, name: names[k] ?? k, sub: sub, seconds: v, placeId: cities ? nil : pids[k])
        }
        return Report(from: from, to: to, bucket: bucket, label: label, total: totals.values.reduce(0, +), points: pts, names: chartNames, rows: rows)
    }

    /// Hours connected per weekday (Mon=0) and hour of day.
    func heat(from: Date, to: Date) -> [[Double]] {
        let cal = Calendar.current, now = Date()
        var grid = [[Double]](repeating: [Double](repeating: 0, count: 24), count: 7)
        for r in store.sessions(from: from, to: min(to, now)) {
            var cur = max(r.start, from); let end = min(r.end, to, now)
            while cur < end {
                guard let hs = cal.dateInterval(of: .hour, for: cur)?.end, hs > cur else { break }
                let seg = min(end, hs).timeIntervalSince(cur)
                grid[(cal.component(.weekday, from: cur) + 5) % 7][cal.component(.hour, from: cur)] += seg / 3600
                cur = hs
            }
        }
        return grid
    }

    func activeDays(from: Date, to: Date) -> Int {
        let cal = Calendar.current, now = Date()
        var days = Set<Date>()
        for r in store.sessions(from: from, to: min(to, now)) {
            var d = cal.startOfDay(for: max(r.start, from)); let end = min(r.end, to, now)
            while d < end { days.insert(d); d = cal.date(byAdding: .day, value: 1, to: d) ?? end }
        }
        return days.count
    }

    func placeTable(from: Date, to: Date) -> [PlaceRowData] {
        let now = Date()
        let rows = store.sessions(from: from, to: min(to, now))
        var by: [Int64: [SessionRow]] = [:]
        for r in rows { if let p = r.placeId { by[p, default: []].append(r) } }
        let total = by.values.flatMap { $0 }.reduce(0.0) { $0 + max(0, min($1.end, to, now).timeIntervalSince(max($1.start, from))) }
        return by.compactMap { (pid, ss) -> PlaceRowData? in
            guard let p = places[pid] else { return nil }
            let durs = ss.map { max(0, min($0.end, to, now).timeIntervalSince(max($0.start, from))) }
            let secs = durs.reduce(0, +)
            let st = stats(pid)
            return PlaceRowData(id: pid, name: p.displayName, city: p.city ?? "—", seconds: secs, share: total > 0 ? secs / total : 0,
                                visits: ss.count, avgStay: secs / Double(max(ss.count, 1)), longest: durs.max() ?? 0,
                                lastSeen: ss.map(\.end).max() ?? from, avgDown: st.avgDown, avgRssi: st.avgRssi,
                                avgRTT: st.avgRTT, slowestHour: st.slowestHour)
        }.sorted { $0.seconds > $1.seconds }
    }

    func sessionLog(from: Date, to: Date, place: Int64?, limit: Int = 300) -> [LogRow] {
        let now = Date()
        return store.sessions(from: from, to: min(to, now)).reversed()
            .filter { place == nil || $0.placeId == place }.prefix(limit).map { r in
                LogRow(id: r.id, start: r.start, duration: r.end.timeIntervalSince(r.start), place: r.placeId.flatMap { places[$0]?.displayName } ?? "Unknown", network: r.ssid)
            }
    }

    func stats(_ id: Int64) -> PlaceStats {
        var st = PlaceStats()
        let t = store.placeTotals(id); st.total = t.seconds; st.visits = t.visits
        let all = store.samples(place: id)
        let speed = all.filter { $0.kind == "speed" }
        st.tests = speed.count
        func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        st.avgDown = avg(speed.compactMap(\.down)); st.avgUp = avg(speed.compactMap(\.up))
        let live = all.filter { $0.kind == "live" }
        st.avgRTT = avg(live.compactMap(\.rtt))
        st.avgRssi = avg(live.compactMap { $0.rssi.map(Double.init) }).map(Int.init)
        var byHour: [Int: [Double]] = [:]
        for s in live { if let r = s.rtt { byHour[Calendar.current.component(.hour, from: s.ts), default: []].append(r) } }
        st.slowestHour = byHour.filter { $0.value.count >= 4 }.max { (avg($0.value) ?? 0) < (avg($1.value) ?? 0) }?.key
        return st
    }
}
