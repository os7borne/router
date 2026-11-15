import SwiftUI
import Charts
import AppKit

enum Tab: String, CaseIterable { case networks = "Networks", signals = "Signals", live = "Live", places = "Places", tools = "Tools" }

struct ContentView: View {
    @EnvironmentObject var w: WiFiManager
    @State private var tab: Tab = .networks
    @State private var pwFor: String?
    @State private var pw = ""
    @State private var band = "5 GHz"
    @State private var forward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if w.locationDenied { locationBanner }
            banner
            if let e = w.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
                    Text(e).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { w.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain)
                }.padding(10).background(Theme.bad.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
            if w.powered {
                tabBar
                ZStack {
                    switch tab {
                    case .networks: networkList
                    case .signals: signals
                    case .live: live
                    case .places: PlacesView(t: w.tracker)
                    case .tools: tools
                    }
                }
                .id(tab)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .frame(height: 340).clipped()
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        .background(SwipeCatcher { dir in step(dir) })
    }

    /// Move to the next (+1) or previous (-1) panel.
    func step(_ dir: Int) {
        let all = Tab.allCases
        guard w.powered, let i = all.firstIndex(of: tab) else { return }
        let n = i + dir
        guard all.indices.contains(n) else { return }
        select(all[n])
    }

    func select(_ t: Tab) {
        guard t != tab else { return }
        let all = Tab.allCases
        forward = (all.firstIndex(of: t) ?? 0) > (all.firstIndex(of: tab) ?? 0)
        withAnimation(.easeOut(duration: 0.22)) { tab = t }
    }

    var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { select(t) } label: {
                    Text(t.rawValue).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(tab == t ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(3).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: header / banner
    var statusColor: Color {
        switch w.status {
        case .connected: return .green
        case .hotspot: return .green
        case .weak, .loginRequired: return .orange
        case .noInternet: return .red
        default: return .secondary
        }
    }
    var statusText: String {
        switch w.status {
        case .off: return "Wi-Fi is off"
        case .disconnected: return "Not connected"
        case .connected: return "Connected"
        case .hotspot: return "Personal hotspot"
        case .weak: return "Weak signal"
        case .loginRequired: return "Login required"
        case .noInternet: return "No internet"
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppMark(gradient: w.status == .loginRequired ? Theme.amber : Theme.brand,
                        symbol: w.status == .loginRequired ? "lock.fill" : (w.powered ? "wifi" : "wifi.slash"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.powered ? (w.ssid ?? "No network") : "Wi-Fi").font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle().fill(w.headline.color).frame(width: 7, height: 7)
                        Text(w.headline.text).font(.system(size: 12, weight: .medium)).foregroundStyle(w.headline.color)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { w.powered }, set: { w.setPower($0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Theme.good)
            }
            if w.powered, w.ssid != nil {
                Text(w.advice).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) { ForEach(w.activities) { activityChip($0) }; Spacer(minLength: 0) }
                HStack(spacing: 8) {
                    chip("Signal", w.quality.word, w.quality.color, w.showTech ? "\(w.rssi) dBm" : nil,
                         help: "How strong the connection to your router is. Closer = better.")
                    chip("Speed", w.speedWord.word, w.speedWord.color, w.showTech ? "\(Int(w.txRate)) Mbps" : nil,
                         help: "How fast your Mac and router can talk to each other. This is not your internet speed — use Tools → Speed test for that.")
                    chip("Interference", w.interference.word, w.interference.color, w.showTech ? "SNR \(w.snr) dB" : nil,
                         help: "How much other devices and nearby networks are drowning out your signal.")
                }
            }
        }
    }

    func activityChip(_ a: Activity) -> some View {
        let c: Color = a.level == 2 ? Theme.good : a.level == 1 ? Theme.warn : Theme.bad
        return HStack(spacing: 3) {
            Text(a.name).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
            Image(systemName: a.level == 2 ? "checkmark" : a.level == 1 ? "minus" : "xmark").font(.system(size: 8, weight: .bold))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .foregroundStyle(c).background(c.opacity(0.14), in: Capsule())
        .help(a.level == 2 ? "\(a.name): should work well" : a.level == 1 ? "\(a.name): may struggle" : "\(a.name): not recommended right now")
    }

    func chip(_ t: String, _ v: String, _ c: Color, _ tech: String?, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.uppercased()).font(.system(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
            Text(v).font(.system(size: 13, weight: .semibold)).foregroundStyle(c).lineLimit(1)
            if let tech { Text(tech).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card(8).help(help)
    }

    @ViewBuilder var banner: some View {
        if let b = w.betterOption, w.status == .connected || w.status == .weak {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(Theme.accent)
                Text("**\(b.ssid)** has a stronger signal.").font(.caption)
                Spacer()
                Button("Switch") { Task { await w.connect(b, password: nil) } }.buttonStyle(Pill(fill: Theme.accent, fg: .black))
            }.padding(10).background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        }
        if w.status == .loginRequired {
            HStack {
                Image(systemName: "lock.shield").foregroundStyle(.orange)
                Text("This network needs a login.").font(.caption)
                Spacer()
                Button("Sign in") { w.openLogin() }.buttonStyle(Pill(fill: Theme.warn, fg: .black))
            }.padding(10).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        } else if w.status == .noInternet {
            HStack {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.red)
                Text("Connected, but no internet.").font(.caption)
                Spacer()
                Button("Diagnose") { select(.tools); w.runDiagnostics() }.buttonStyle(Pill())
            }.padding(10).background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        } else if w.status == .weak {
            HStack {
                Image(systemName: "wifi").foregroundStyle(.orange)
                Text("Weak signal. A stronger network may be nearby.").font(.caption)
            }.padding(10).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    func stat(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.system(.caption, design: .monospaced))
        }
    }

    var locationBanner: some View {
        HStack {
            Text("Location access is needed to read network names.").font(.caption)
            Button("Open") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
            }.controlSize(.small)
        }
    }

    var footer: some View {
        VStack(spacing: 8) {
        HStack {
            Menu {
                Button("Settings…") { openSettingsAction?() }.keyboardShortcut(",")
                Toggle("Smart auto-connect (★ favorites)", isOn: $w.smartRoam)
                Toggle("Notifications", isOn: $w.notify)
                if w.ssid != nil { Button("Disconnect") { w.disconnect() } }
                Button("Wi-Fi Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                }
                if let g = w.gateway { Button("Open router page (\(g))") { NSWorkspace.shared.open(URL(string: "http://\(g)")!) } }
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).fixedSize()
            Text("⌃⌥W").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.link).font(.caption).keyboardShortcut("q")
        }
        CreditLine().frame(maxWidth: .infinity)
        }
    }

    // MARK: networks tab
    var networkList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(w.networks.count) networks").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if w.scanning { ProgressView().controlSize(.small) }
                else { Button { Task { await w.scan() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless) }
            }
            ScrollView { VStack(spacing: 0) { ForEach(w.networks) { row($0) } } }
        }
    }

    func row(_ n: Net) -> some View {
        let isCurrent = n.ssid == w.ssid
        let fav = w.favorites.contains(n.ssid)
        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button { w.toggleFavorite(n.ssid) } label: {
                    Image(systemName: fav ? "star.fill" : "star").font(.system(size: 13))
                        .foregroundStyle(fav ? Theme.warn : Color.secondary.opacity(0.7))
                }.buttonStyle(.plain).help("Favorite — used by smart auto-connect")
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.ssid).font(.system(size: 14, weight: isCurrent ? .semibold : .medium)).lineLimit(1)
                    Text(meta(n, isCurrent)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .help("\(n.band): \(WiFiManager.bandHint(n.band)). Signal: \(WiFiManager.quality(rssi: n.rssi).word).")
                }
                Spacer()
                if w.connecting == n.ssid { ProgressView().controlSize(.small) }
                if n.secure { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
                if isCurrent { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent) }
                SignalBars(rssi: n.rssi)
            }
            .padding(.horizontal, 10).frame(height: 46)
            .background(isCurrent ? Theme.accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isCurrent else { return }
                if n.secure && !n.known { pwFor = n.ssid; pw = "" }
                else { Task { await w.connect(n, password: nil) } }
            }
            .contextMenu { if n.known { Button("Forget Network") { w.forget(n.ssid) } } }
            if pwFor == n.ssid || w.needsPassword == n.ssid {
                HStack {
                    SecureField("Password", text: $pw).textFieldStyle(.roundedBorder).onSubmit { submit(n) }
                    Button("Join") { submit(n) }.buttonStyle(Pill(fill: Theme.accent, fg: .black)).disabled(pw.isEmpty)
                }.padding(.horizontal, 10).padding(.bottom, 4)
            }
        }
    }

    func meta(_ n: Net, _ current: Bool) -> String {
        var parts: [String] = []
        if current { parts.append("Connected") } else if w.favorites.contains(n.ssid) { parts.append("Favorite") } else if n.known { parts.append("Saved") }
        parts.append(WiFiManager.quality(rssi: n.rssi).word)
        parts.append(n.band)
        if !n.secure { parts.append("No password") }
        if w.showTech { parts.append("\(n.rssi) dBm") }
        return parts.joined(separator: " · ")
    }

    func submit(_ n: Net) {
        let p = pw; pwFor = nil; pw = ""; w.needsPassword = nil
        Task { await w.connect(n, password: p) }
    }

    // MARK: signals tab (all detected APs + channel congestion)
    var signals: some View {
        let bands = w.bandsPresent
        let b = bands.contains(band) ? band : (bands.contains(w.bandName) ? w.bandName : (bands.first ?? "5 GHz"))
        let (loads, rec) = w.channelLoads(band: b)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Which channel is least crowded?").font(.subheadline.bold())
                Spacer()
                if bands.count > 1 {
                    Picker("", selection: $band) { ForEach(bands, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
            }
            Chart(loads) { c in
                BarMark(x: .value("Channel", String(c.ch)), y: .value("Load", c.load))
                    .foregroundStyle(c.kind == 1 ? Color.blue : c.kind == 2 ? Color.green : Color.gray.opacity(0.5))
            }
            .chartYAxis(.hidden).frame(height: 70)
            HStack(spacing: 4) {
                if let rec {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    Text(rec == w.channelNum && b == w.bandName ? "You're already on the clearest channel."
                         : "Set your router to channel \(rec) for less interference.").font(.caption)
                }
                Spacer()
                Text("\(w.aps.count) nearby").font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(w.aps) { ap in
                        HStack(spacing: 6) {
                            Text(ap.ssid).lineLimit(1).font(.caption)
                                .fontWeight(ap.ssid == w.ssid ? .semibold : .regular)
                            Spacer()
                            Text("Ch \(ap.channel)\(ap.width.isEmpty ? "" : "/\(ap.width)")").font(.caption2).foregroundStyle(.secondary)
                            Text(ap.band).font(.caption2).foregroundStyle(.secondary)
                            ProgressView(value: max(0, min(1, Double(ap.rssi + 95) / 55)))
                                .frame(width: 50).tint(ap.rssi > -60 ? .green : ap.rssi > -75 ? .orange : .red)
                            Text(w.showTech ? "\(ap.rssi)" : WiFiManager.quality(rssi: ap.rssi).word).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
    }

    // MARK: live tab
    var live: some View {
        VStack(alignment: .leading, spacing: 8) {
            if w.samples.count < 2 {
                Text(w.ssid == nil ? "Connect to a network to see live data." : "Collecting samples…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if let st = w.stability { HStack(spacing: 6) { Circle().fill(st.color).frame(width: 7, height: 7); Text(st.text).font(.caption.weight(.medium)) } }
                Text("Signal strength — higher is better").font(.subheadline.bold())
                Chart(w.samples) { s in
                    LineMark(x: .value("t", s.t), y: .value("dBm", s.rssi)).foregroundStyle(.blue)
                    AreaMark(x: .value("t", s.t), yStart: .value("floor", -95), yEnd: .value("dBm", s.rssi)).foregroundStyle(.blue.opacity(0.12))
                }
                .chartYScale(domain: -95 ... -30).frame(height: 100)
                let lat = w.samples.compactMap(\.latency)
                HStack {
                    Text("Response time — lower is better").font(.subheadline.bold())
                    Spacer()
                    if !lat.isEmpty {
                        Text(String(format: "typically %.0f ms", lat.reduce(0, +) / Double(lat.count)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Chart(w.samples.filter { $0.latency != nil }) { s in
                    LineMark(x: .value("t", s.t), y: .value("ms", s.latency ?? 0)).foregroundStyle(.purple)
                }.frame(height: 100)
                Text("Last \(max(1, w.samples.count * 4 / 60)) min").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: tools tab
    var tools: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                speedCard
                diagCard
            }
        }
    }

    var speedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed test").font(.subheadline.bold())
                Spacer()
                if w.testing { ProgressView().controlSize(.small); Text("Measuring…").font(.caption) }
                else { Button("Run") { w.runSpeedTest() }.buttonStyle(Pill()) }
            }
            if let r = w.history.first {
                HStack(spacing: 14) {
                    stat("Download", String(format: "%.0f Mbps", r.down))
                    stat("Upload", String(format: "%.0f Mbps", r.up))
                    stat("Latency", String(format: "%.0f ms", r.rtt))
                    if let rpm = r.rpm { stat("Snappiness", rpm > 1000 ? "Great" : rpm > 300 ? "Good" : "Laggy") }
                }
                Text(WiFiManager.speedVerdict(r.down)).font(.system(size: 12, weight: .semibold))
                Text(r.date.formatted(.relative(presentation: .named)) + " · " + r.ssid)
                    .font(.caption2).foregroundStyle(.secondary)
                if w.history.count > 1 {
                    Chart(w.history.reversed()) { h in
                        BarMark(x: .value("d", h.date), y: .value("Mbps", h.down)).foregroundStyle(.blue.opacity(0.6))
                    }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 36)
                }
            }
        }
        .card(12)
    }

    var diagCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Diagnostics").font(.subheadline.bold())
                Spacer()
                if w.diagRunning { ProgressView().controlSize(.small) }
                else { Button("Run") { w.runDiagnostics() }.buttonStyle(Pill()) }
            }
            ForEach(w.diag) { s in
                HStack(spacing: 6) {
                    icon(s.state)
                    Text(s.id).font(.caption)
                    Spacer()
                    Text(s.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if !w.diagVerdict.isEmpty {
                Text(w.diagVerdict).font(.caption.bold())
                    .foregroundStyle(w.diagVerdict.hasPrefix("Everything") ? .green : .orange)
            }
            if w.status == .loginRequired { Button("Sign in to network") { w.openLogin() }.buttonStyle(Pill(fill: Theme.warn, fg: .black)) }
        }
        .card(12)
    }

    @ViewBuilder func icon(_ s: DiagStep.State) -> some View {
        switch s {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.mini).frame(width: 14, height: 14)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .fail: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}


/// Detects a two-finger horizontal trackpad swipe (or horizontal wheel) over the popover
/// and reports +1 (next panel) or -1 (previous panel). Vertical scrolling is left alone.
struct SwipeCatcher: NSViewRepresentable {
    var onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.view = v
        context.coordinator.install()
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onSwipe = onSwipe }
    func makeCoordinator() -> Coordinator { Coordinator(onSwipe) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    final class Coordinator {
        var onSwipe: (Int) -> Void
        weak var view: NSView?
        private var monitor: Any?
        private var acc: CGFloat = 0
        private var fired = false
        init(_ f: @escaping (Int) -> Void) { onSwipe = f }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let win = self.view?.window, e.window === win else { return e }
                if e.phase == .began || e.phase == .mayBegin { self.acc = 0; self.fired = false }
                let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
                guard abs(dx) > abs(dy) else { return e }          // mostly vertical: let it scroll
                if !self.fired {
                    self.acc += dx
                    if abs(self.acc) > 50 {
                        self.fired = true
                        self.onSwipe(self.acc < 0 ? 1 : -1)        // fingers left → next panel
                    }
                }
                if e.phase == .ended || e.phase == .cancelled || e.momentumPhase == .ended { self.acc = 0; self.fired = false }
                return nil
            }
        }
        func remove() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
        deinit { remove() }
    }
}
