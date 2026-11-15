import SwiftUI

enum Theme {
    static let brand = LinearGradient(colors: [Color(red: 0.357, green: 0.549, blue: 1.0), Color(red: 0.133, green: 0.827, blue: 0.933)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let amber = LinearGradient(colors: [Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.98, green: 0.45, blue: 0.09)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accent = Color(red: 0.37, green: 0.72, blue: 1.0)
    static let good = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let warn = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let bad = Color(red: 0.97, green: 0.44, blue: 0.44)
    static let series: [Color] = [accent, Color(red: 0.65, green: 0.55, blue: 0.98), good, warn,
                                  Color(red: 0.96, green: 0.55, blue: 0.75), Color(red: 0.35, green: 0.85, blue: 0.85),
                                  Color(red: 0.98, green: 0.60, blue: 0.30), Color(red: 0.50, green: 0.55, blue: 0.95)]
    static func seriesColors(_ names: [String]) -> [Color] { names.enumerated().map { $1 == "Other" ? Color.gray : series[$0 % series.count] } }
    static func seriesColor(_ i: Int, top: Int) -> Color { i < top ? series[i % series.count] : Color.gray }
}

struct Card: ViewModifier {
    var padding: CGFloat = 10
    func body(content: Content) -> some View {
        content.padding(padding).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
extension View { func card(_ p: CGFloat = 10) -> some View { modifier(Card(padding: p)) } }

struct SignalBars: View {
    let rssi: Int
    var level: Int { rssi > -60 ? 4 : rssi > -70 ? 3 : rssi > -80 ? 2 : 1 }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < level ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }.frame(height: 15).accessibilityLabel("Signal \(rssi) dBm")
    }
}

struct AppMark: View {
    var gradient: LinearGradient = Theme.brand
    var symbol = "wifi"
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(gradient)
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.white))
    }
}

struct Pill: ButtonStyle {
    var fill: Color = Color.primary.opacity(0.1)
    var fg: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// "Mini project by …" credit line shown in the popover and Settings.
struct CreditLine: View {
    var body: some View {
        Text("Mini project by [Osborne Saldanha](https://osborne.vc)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .tint(Theme.accent)
    }
}
