import SwiftUI
import Charts

/// Compact places summary shown in the menubar popover. Fine-grained analysis lives in AnalyticsView.
struct PlacesView: View {
    @EnvironmentObject var w: WiFiManager
    @ObservedObject var t: PlaceTracker
    @State private var period: Period = .week

    var body: some View {
        let r = t.report(period: period, offset: 0, cities: false, topN: 3)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                nowCard
                HStack(spacing: 2) {
                    ForEach(Period.simple) { p in
                        Button { period = p } label: {
                            Text(p.rawValue).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                                .background(period == p ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(period == p ? Color.primary : Color.secondary).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(2).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

                if r.total == 0 {
                    Text(t.locationDenied ? "Allow Location access in Settings to see where you connect."
                         : "Nothing tracked for this period yet. Stay connected and it will show up here.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(fmtDuration(r.total)).font(.system(size: 22, weight: .bold)).monospacedDigit()
                        Text("connected · \(r.label.lowercased())").font(.caption).foregroundStyle(.secondary)
                    }
                    Chart(r.points) { p in
                        BarMark(x: .value("Time", p.start, unit: r.bucket), y: .value("Hours", p.hours))
                            .foregroundStyle(by: .value("Place", p.series))
                    }
                    .chartForegroundStyleScale(domain: r.names, range: Theme.seriesColors(r.names))
                    .chartLegend(.hidden).timeAxes(r).frame(height: 110)
                    VStack(spacing: 0) {
                        ForEach(Array(r.rows.prefix(3).enumerated()), id: \.element.id) { i, row in
                            Button { openAnalyticsAction?(row.placeId) } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Theme.seriesColor(i, top: 3)).frame(width: 8, height: 8)
                                    Text(row.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Spacer()
                                    Text(fmtDuration(row.seconds)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    Text("\(Int((row.seconds / max(r.total, 1)) * 100))%").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                                }.padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if r.rows.count > 3 { Text("+ \(r.rows.count - 3) more places").font(.caption).foregroundStyle(.secondary).padding(.top, 2).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
                Button { openAnalyticsAction?(nil) } label: {
                    HStack(spacing: 6) { Text("View details"); Image(systemName: "arrow.up.forward.app") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(Pill(fill: Theme.accent.opacity(0.18), fg: Theme.accent))
            }
        }
    }

    var nowCard: some View {
        let cur = t.currentPlaceId.flatMap { t.places[$0] }
        return HStack(spacing: 10) {
            Image(systemName: t.paused ? "pause.circle.fill" : "mappin.circle.fill").font(.system(size: 22))
                .foregroundStyle(t.paused ? Color.secondary : Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.paused ? "Tracking paused" : cur?.displayName ?? (w.ssid == nil ? "Not connected" : "Locating…"))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(sub(cur)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if t.paused { Button("Resume") { t.paused = false }.buttonStyle(Pill()) }
        }.card(10)
    }

    func sub(_ cur: Place?) -> String {
        if t.paused { return "Time isn't being counted" }
        guard let cur else { return w.ssid == nil ? "Time counts while you're connected" : "Finding where you are" }
        return [cur.subtitle, fmtDuration(t.todayTotal(for: cur.id)) + " here today"].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Gives the time chart axes people can read: real calendar labels on X
/// (hours of the day / weekdays / day numbers / months) and "1h 30m" style
/// labels on Y, with the X range covering the whole period, not just the data.
extension View {
    func timeAxes(_ r: Report) -> some View {
        self
            .chartXScale(domain: r.from...max(r.to, r.from.addingTimeInterval(1)))
            .chartXAxis {
                switch r.bucket {
                case .hour:
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.hour())
                    }
                case .day where r.to.timeIntervalSince(r.from) <= 8 * 86400:
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                case .day:
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.day())
                    }
                default:
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let h = v.as(Double.self) { Text(h == 0 ? "0" : fmtDuration(h * 3600)).font(.system(size: 10)) }
                    }
                }
            }
    }
}
