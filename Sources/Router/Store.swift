import Foundation
import SQLite3

struct Place: Identifiable, Hashable {
    var id: Int64
    var name: String?
    var ssid: String?
    var lat: Double?
    var lon: Double?
    var area: String?
    var city: String?
    var country: String?
    var displayName: String { name ?? area ?? city ?? ssid ?? "Unknown place" }
    var subtitle: String? {
        // Location first; the Wi-Fi name is only secondary context.
        var p: [String] = []
        if name != nil, let a = area { p.append(a) }
        if let c = city, c != (name ?? area) { p.append(c) }
        if let s = ssid { p.append("via \(s)") }
        return p.isEmpty ? nil : p.joined(separator: " · ")
    }
}
struct SessionRow { let id: Int64; let placeId: Int64?; let ssid: String; let start: Date; let end: Date }
struct SampleRow { let ts: Date; let kind: String; let down: Double?; let up: Double?; let rtt: Double?; let rssi: Int? }

/// Tiny SQLite wrapper. Local-only: ~/Library/Application Support/Router/router.sqlite
final class Store {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Router")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sqlite3_open(dir.appendingPathComponent("router.sqlite").path, &db)
        run("PRAGMA journal_mode=WAL")
        run("CREATE TABLE IF NOT EXISTS places(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ssid TEXT, lat REAL, lon REAL, area TEXT, city TEXT, country TEXT, created REAL)")
        run("CREATE TABLE IF NOT EXISTS sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, place_id INTEGER, ssid TEXT, start REAL, end REAL)")
        run("CREATE TABLE IF NOT EXISTS samples(id INTEGER PRIMARY KEY AUTOINCREMENT, place_id INTEGER, ts REAL, kind TEXT, down REAL, up REAL, rtt REAL, rssi INTEGER)")
        run("CREATE INDEX IF NOT EXISTS s_start ON sessions(start)")
        run("CREATE INDEX IF NOT EXISTS smp_place ON samples(place_id, ts)")
    }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) -> Int64 {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        sqlite3_step(st)
        return sqlite3_last_insert_rowid(db)
    }

    func query<R>(_ sql: String, _ args: [Any?] = [], _ map: (OpaquePointer) -> R) -> [R] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let s = st else { return [] }
        defer { sqlite3_finalize(s) }
        bind(s, args)
        var out: [R] = []
        while sqlite3_step(s) == SQLITE_ROW { out.append(map(s)) }
        return out
    }

    private func bind(_ st: OpaquePointer?, _ args: [Any?]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            guard let a else { sqlite3_bind_null(st, idx); continue }
            switch a {
            case let v as Int64: sqlite3_bind_int64(st, idx, v)
            case let v as Int: sqlite3_bind_int64(st, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(st, idx, v)
            case let v as Date: sqlite3_bind_double(st, idx, v.timeIntervalSince1970)
            case let v as String: sqlite3_bind_text(st, idx, v, -1, transient)
            default: sqlite3_bind_null(st, idx)
            }
        }
    }

    private func text(_ s: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : sqlite3_column_text(s, i).map { String(cString: $0) }
    }
    private func dbl(_ s: OpaquePointer, _ i: Int32) -> Double? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : sqlite3_column_double(s, i)
    }

    // MARK: places
    func allPlaces() -> [Place] {
        query("SELECT id,name,ssid,lat,lon,area,city,country FROM places") { s in
            Place(id: sqlite3_column_int64(s, 0), name: text(s, 1), ssid: text(s, 2), lat: dbl(s, 3), lon: dbl(s, 4),
                  area: text(s, 5), city: text(s, 6), country: text(s, 7))
        }
    }
    func insertPlace(ssid: String?, lat: Double?, lon: Double?) -> Place {
        let id = run("INSERT INTO places(ssid,lat,lon,created) VALUES(?,?,?,?)", [ssid, lat, lon, Date()])
        return Place(id: id, name: nil, ssid: ssid, lat: lat, lon: lon, area: nil, city: nil, country: nil)
    }
    func update(_ p: Place) {
        run("UPDATE places SET name=?, ssid=?, lat=?, lon=?, area=?, city=?, country=? WHERE id=?",
            [p.name, p.ssid, p.lat, p.lon, p.area, p.city, p.country, p.id])
    }
    func deletePlace(_ id: Int64) {
        run("DELETE FROM sessions WHERE place_id=?", [id]); run("DELETE FROM samples WHERE place_id=?", [id]); run("DELETE FROM places WHERE id=?", [id])
    }
    func wipe() { run("DELETE FROM sessions"); run("DELETE FROM samples"); run("DELETE FROM places") }

    // MARK: sessions
    func startSession(placeId: Int64?, ssid: String, at: Date) -> Int64 {
        run("INSERT INTO sessions(place_id,ssid,start,end) VALUES(?,?,?,?)", [placeId, ssid, at, at])
    }
    func heartbeat(_ id: Int64, _ at: Date) { run("UPDATE sessions SET end=? WHERE id=?", [at, id]) }
    func setSessionPlace(_ id: Int64, _ place: Int64) { run("UPDATE sessions SET place_id=? WHERE id=?", [place, id]) }
    func sessions(from: Date, to: Date) -> [SessionRow] {
        query("SELECT id,place_id,ssid,start,end FROM sessions WHERE end>? AND start<? ORDER BY start", [from, to]) { s in
            SessionRow(id: sqlite3_column_int64(s, 0), placeId: sqlite3_column_type(s, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 1),
                       ssid: text(s, 2) ?? "", start: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                       end: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)))
        }
    }
    func earliest() -> Date? {
        query("SELECT MIN(start) FROM sessions") { s in
            sqlite3_column_type(s, 0) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 0))
        }.first ?? nil
    }
    func placeTotals(_ id: Int64) -> (seconds: Double, visits: Int) {
        query("SELECT COALESCE(SUM(end-start),0), COUNT(*) FROM sessions WHERE place_id=?", [id]) { s in
            (sqlite3_column_double(s, 0), Int(sqlite3_column_int64(s, 1)))
        }.first ?? (0, 0)
    }

    // MARK: samples
    func addSample(place: Int64, kind: String, down: Double?, up: Double?, rtt: Double?, rssi: Int?) {
        run("INSERT INTO samples(place_id,ts,kind,down,up,rtt,rssi) VALUES(?,?,?,?,?,?,?)", [place, Date(), kind, down, up, rtt, rssi])
    }
    func samples(place: Int64) -> [SampleRow] {
        query("SELECT ts,kind,down,up,rtt,rssi FROM samples WHERE place_id=? ORDER BY ts", [place]) { s in
            SampleRow(ts: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), kind: text(s, 1) ?? "", down: dbl(s, 2), up: dbl(s, 3),
                      rtt: dbl(s, 4), rssi: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, 5)))
        }
    }
}
