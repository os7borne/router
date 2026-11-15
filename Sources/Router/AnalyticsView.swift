import SwiftUI
import Charts

struct AnalyticsView: View {
    @ObservedObject var t: PlaceTracker
    @State private var period: Period = .month
    @State private var offset = 0
    @State private var byCity = false
    @State private var selection: Int64?
    @State private var sort = [KeyPathComparator(\PlaceRowData.seconds, order: .reverse)]

    var body: some View {
        let r = t.report(period: period, offset: offset, cities: byCity, topN: 8)
        let rows = t.placeTable(from: r.from, to: r.to).sorted(using: sort)
        return VStack(spacing: 0) {
            toolbar(r)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if r.total == 0 {
                        Text("Nothing tracked in this period.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(60)
                    } else {
                        kpis(r, rows)
                        card("Time connected") { timeChart(r) }
                        HStack(alignment: .top, spacing: 16) {
                            card("When you're connected") { heatmap(r) }
                            card("Download speed by place") { quality(rows) }
                        }
                        card("Places") { table(rows) }
                        if let id = selection, let p = t.places[id] { PlaceDetailCard(t: t, place: p) { selection = nil } }
                        card(selection.flatMap { t.places[$0]?.displayName }.map { "Sessions · \($0)" } ?? "Sessions") { log(r) }
                    }
                }.padding(20)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .onAppear { selection = t.focusPlace }
        .onChange(of: t.focusPlace) { selection = $0 }
    }

    // MARK: pieces
    func toolbar(_ r: Report) -> some View {
        HStack(spacing: 14) {
            Picker("", selection: $period) { ForEach(Period.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 290)
                .onChange(of: period) { _ in offset = 0 }
            HStack(spacing: 6) {
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }.disabled(period == .all)
                Text(r.label).font(.system(size: 13, weight: .semibold)).frame(minWidth: 110)
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0 || period == .all)
            }.buttonStyle(.borderless)
            Spacer()
            Picker("", selection: $byCity) { Text("Places").tag(false); Text("Cities").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    func kpis(_ r: Report, _ rows: [PlaceRowData]) -> some View {
        let days = max(1, t.activeDays(from: r.from, to: r.to))
        let longest = rows.max { $0.longest < $1.longest }
        return HStack(spacing: 12) {
            kpi("Total connected", fmtDuration(r.total), nil)
            kpi("Places", "\(rows.count)", byCity ? "\(r.rows.count) cities" : nil)
            kpi("Per active day", fmtDuration(r.total / Double(days)), "\(days) active day\(days == 1 ? "" : "s")")
            kpi("Longest stay", fmtDuration(longest?.longest ?? 0), longest?.name)
        }
    }
    func kpi(_ k: String, _ v: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
            Text(v).font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(sub ?? " ").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).card(14)
    }

    func card<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            c()
        }.frame(maxWidth: .infinity, alignment: .leading).card(14)
    }

    func timeChart(_ r: Report) -> some View {
        Chart(r.points) { p in
            BarMark(x: .value("Time", p.start, unit: r.bucket), y: .value("Hours", p.hours))
                .foregroundStyle(by: .value("Place", p.series))
        }
        .chartForegroundStyleScale(domain: r.names, range: Theme.seriesColors(r.names))
        .timeAxes(r)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
        .frame(height: 230)
    }

    func heatmap(_ r: Report) -> some View {
        let grid = t.heat(from: r.from, to: r.to)
        let maxV = max(grid.flatMap { $0 }.max() ?? 1, 0.01)
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return VStack(alignment: .leading, spacing: 4) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<7, id: \.self) { d in
                    GridRow {
                        Text(days[d]).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                        ForEach(0..<24, id: \.self) { h in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent.opacity(grid[d][h] == 0 ? 0.06 : 0.2 + 0.8 * grid[d][h] / maxV))
                                .frame(height: 18).help("\(days[d]) \(h):00 — \(fmtDuration(grid[d][h] * 3600))")
                        }
                    }
                }
                GridRow {
                    Color.clear.frame(width: 28, height: 1)
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 6 == 0 ? "\(h)" : "").font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
            }
            Text("Darker = more time connected, by hour of day").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    func quality(_ rows: [PlaceRowData]) -> some View {
        let withSpeed = rows.filter { $0.avgDown != nil }
        return Group {
            if withSpeed.isEmpty {
                Text("Run a speed test at a place (Tools tab) to compare Wi-Fi across places.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(withSpeed) { r in
                    BarMark(x: .value("Mbps", r.avgDown ?? 0), y: .value("Place", r.name)).foregroundStyle(Theme.accent.gradient)
                        .annotation(position: .trailing) { Text(String(format: "%.0f", r.avgDown ?? 0)).font(.system(size: 10)).foregroundStyle(.secondary) }
                }.frame(height: max(100, CGFloat(withSpeed.count) * 30))
            }
        }
    }

    func table(_ rows: [PlaceRowData]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn("Place", value: \.name) { r in
                Text(r.name).fontWeight(.medium)
            }.width(min: 120, ideal: 160)
            TableColumn("City", value: \.city).width(min: 80, ideal: 110)
            TableColumn("Time", value: \.seconds) { r in Text(fmtDuration(r.seconds)).monospacedDigit() }.width(70)
            TableColumn("Share") { r in Text("\(Int(r.share * 100))%").monospacedDigit() }.width(50)
            TableColumn("Visits", value: \.visits) { r in Text("\(r.visits)").monospacedDigit() }.width(50)
            TableColumn("Avg stay", value: \.avgStay) { r in Text(fmtDuration(r.avgStay)).monospacedDigit() }.width(70)
            TableColumn("Last seen", value: \.lastSeen) { r in Text(r.lastSeen.formatted(.relative(presentation: .named))) }.width(min: 90, ideal: 110)
            TableColumn("Download") { r in Text(r.avgDown.map { String(format: "%.0f Mbps", $0) } ?? "—").monospacedDigit() }.width(80)
            TableColumn("Signal") { r in Text(r.avgRssi.map { WiFiManager.quality(rssi: $0).word } ?? "—") }.width(70)
        }
        .frame(height: min(320, CGFloat(rows.count) * 28 + 44))
    }

    func log(_ r: Report) -> some View {
        let items = t.sessionLog(from: r.from, to: r.to, place: selection)
        return Table(items) {
            TableColumn("Start") { i in Text(i.start.formatted(date: .abbreviated, time: .shortened)) }.width(min: 140, ideal: 160)
            TableColumn("Place") { i in Text(i.place) }
            TableColumn("Network") { i in Text(i.network).foregroundStyle(.secondary) }
            TableColumn("Duration") { i in Text(fmtDuration(i.duration)).monospacedDigit() }.width(80)
        }.frame(height: min(300, CGFloat(max(items.count, 1)) * 28 + 44))
    }
}

struct PlaceDetailCard: View {
    @ObservedObject var t: PlaceTracker
    let place: Place
    let onForget: () -> Void
    @State private var name = ""

    var body: some View {
        let s = t.stats(place.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLACE DETAILS").font(.system(size: 10, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
                    if let sub = place.subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                TextField(place.area ?? place.ssid ?? "Name this place (Home, Office…)", text: $name)
                    .textFieldStyle(.roundedBorder).frame(width: 260).onSubmit { t.rename(place.id, name) }
                Button("Forget place") { t.delete(place.id); onForget() }.buttonStyle(Pill(fill: Theme.bad.opacity(0.18), fg: Theme.bad))
            }
            HStack(spacing: 10) {
                cell("All-time", fmtDuration(s.total)); cell("Visits", "\(s.visits)")
                cell("Download", s.avgDown.map { String(format: "%.0f Mbps", $0) } ?? "No test yet")
                cell("Upload", s.avgUp.map { String(format: "%.0f Mbps", $0) } ?? "—")
                cell("Response", s.avgRTT.map { String(format: "%.0f ms", $0) } ?? "—")
                cell("Signal", s.avgRssi.map { WiFiManager.quality(rssi: $0).word } ?? "—")
                cell("Slowest", s.slowestHour.map { hourLabel($0) } ?? "Needs data")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card(14)
        .onAppear { name = place.name ?? "" }
        .onChange(of: place.id) { _ in name = place.name ?? "" }
    }

    func cell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.system(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
            Text(v).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    func hourLabel(_ h: Int) -> String { "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")" }
}
