import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var w: WiFiManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) { content }
            .frame(width: 500, height: 560)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                AppMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Router").font(.system(size: 18, weight: .bold))
                    Text("Wi-Fi control from your menubar").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            group("Connection", [
                .toggle("Smart auto-connect", "Switch to a starred network when your signal gets weak", $w.smartRoam),
                .toggle("Check for login pages", "Spot café and hotel sign-in pages and offer a Sign in button", $w.checkLogin),
            ])
            group("Alerts", [
                .toggle("Notifications", "Tell me when I connect, disconnect, or something goes wrong", $w.notify),
                .toggle("Sound", "Play a sound with alerts", $w.sound),
            ])
            group("Privacy", [.location])
            group("Places", [
                .toggle("Track time at places", "Log where you connect and how long you stay. Stored only on this Mac.",
                        Binding(get: { !w.tracker.paused }, set: { w.tracker.paused = !$0 })),
                .radius,
                .wipe,
            ])
            group("Display", [
                .toggle("Show technical details", "Add the raw numbers (dBm, Mbps) next to the plain-language ratings", $w.showTech),
            ])
            group("General", [
                .toggle("Launch at login", "Start Router when you sign in to your Mac",
                        Binding(get: { w.launchAtLogin }, set: { w.launchAtLogin = $0 })),
                .keys("Global shortcut", "Open Router from anywhere", "⌃ ⌥ W"),
            ])
            group("About", [.feedback])
            CreditLine().frame(maxWidth: .infinity)
            if let e = w.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
    }

    enum Item { case toggle(String, String, Binding<Bool>); case keys(String, String, String); case radius; case wipe; case location; case feedback }

    func group(_ title: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    if i > 0 { Divider().padding(.leading, 14) }
                    row(items[i])
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder func row(_ item: Item) -> some View {
        switch item {
        case let .toggle(t, sub, b):
            HStack(spacing: 14) {
                label(t, sub)
                Toggle("", isOn: b).toggleStyle(.switch).labelsHidden().tint(Theme.good)
            }.padding(.horizontal, 14).padding(.vertical, 11)
        case .radius:
            HStack(spacing: 14) {
                label("Place size", "Spots closer than this count as the same place (\(Int(w.tracker.radius)) m)")
                Slider(value: Binding(get: { w.tracker.radius }, set: { w.tracker.radius = $0 }), in: 50...500, step: 25).frame(width: 130)
            }.padding(.horizontal, 14).padding(.vertical, 11)
        case .location:
            HStack(spacing: 14) {
                label("Location access", w.locationAllowed
                      ? "Allowed. Router can read network names and remember places."
                      : w.locationDenied ? "Off. Network names and places won't work until you turn it on."
                      : "Not set up yet. Needed to read Wi-Fi names and track places.")
                Text(w.locationAllowed ? "Allowed" : w.locationDenied ? "Off" : "Not asked")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(w.locationAllowed ? Theme.good : w.locationDenied ? Theme.bad : Theme.warn)
                if !w.locationAllowed {
                    Button(w.locationUndetermined ? "Allow…" : "Open Settings") { w.requestLocationAccess() }.buttonStyle(Pill())
                }
            }.padding(.horizontal, 14).padding(.vertical, 11)
        case .wipe:
            HStack(spacing: 14) {
                label("Location history", "Delete every place and all tracked time")
                Button("Delete…") { confirmWipe() }.buttonStyle(Pill(fill: Theme.bad.opacity(0.2), fg: Theme.bad))
            }.padding(.horizontal, 14).padding(.vertical, 11)
        case .feedback:
            HStack(spacing: 14) {
                label("Feedback", "Found a bug or have an idea? Send an email.")
                Button("Send feedback") {
                    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    let subject = "Router feedback (v\(v))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Router feedback"
                    if let u = URL(string: "mailto:apps@osborne.vc?subject=\(subject)") { NSWorkspace.shared.open(u) }
                }.buttonStyle(Pill())
            }.padding(.horizontal, 14).padding(.vertical, 11)
        case let .keys(t, sub, k):
            HStack(spacing: 14) {
                label(t, sub)
                Text(k).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }.padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    func confirmWipe() {
        let a = NSAlert()
        a.messageText = "Delete all location history?"
        a.informativeText = "Every place and all tracked time will be removed from this Mac. This can't be undone."
        a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { w.tracker.wipeAll() }
    }

    func label(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 13, weight: .medium))
            Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
