import SwiftUI
import Charts
import AppKit

enum Tab: String, CaseIterable { case networks = "Networks", diagnostics = "Diagnostics", places = "Places" }

struct ContentView: View {
    @EnvironmentObject var w: WiFiManager
    @State private var tab: Tab = .networks
    @State private var pwFor: String?
    @State private var pw = ""
    @State private var band = "5 GHz"
    @State private var forward = true
    /// nil = automatic (open when something is wrong, collapsed when all is well); true/false = the user's choice.
    @State private var statusOpen: Bool?
    @State private var listOpen: Bool?
    @State private var openSections: Set<String> = ["live", "nearby", "speed"]

    var statusOpenNow: Bool { statusOpen ?? !w.healthy }
    var listOpenNow: Bool { listOpen ?? !w.healthy }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if w.locationDenied { locationBanner }
            banner
            publicCard
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
                    case .diagnostics: diagnostics
                    case .places: PlacesView(t: w.tracker)
                    }
                }
                .id(tab)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .frame(height: contentHeight, alignment: .top).clipped()
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        .background(SwipeCatcher { dir in step(dir) })
        .animation(.easeOut(duration: 0.2), value: statusOpenNow)
        .animation(.easeOut(duration: 0.2), value: listOpenNow)
        .onChange(of: w.status) { _ in statusOpen = nil; listOpen = nil }
        .onChange(of: w.ssid) { _ in statusOpen = nil; listOpen = nil }
    }

    /// The Networks panel shrinks to a couple of rows while everything is fine.
    var contentHeight: CGFloat { tab == .networks && !listOpenNow ? 96 : 340 }

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

    // MARK: header / status
    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                if statusOpenNow { statusExpanded } else { statusCollapsed }
            }
        }
    }

    /// One line while all is well: tap to see the details.
    var statusCollapsed: some View {
        Button { statusOpen = true } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.advice).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    (Text("Signal ").foregroundColor(.secondary) + Text(w.quality.word).foregroundColor(w.quality.color)
                     + Text(" · Speed ").foregroundColor(.secondary) + Text(w.speedWord.word).foregroundColor(w.speedWord.color)
                     + Text(" · Interference ").foregroundColor(.secondary) + Text(w.interference.word).foregroundColor(w.interference.color))
                        .font(.system(size: 11)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help("Show what works on this connection")
    }

    var statusExpanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(w.advice).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if w.healthy {
                    Button { statusOpen = false } label: { Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Collapse")
                }
            }
            FlowLayout(spacing: 5) { ForEach(w.activities) { activityChip($0) } }
            HStack(spacing: 8) {
                chip("Signal", w.quality.word, w.quality.color, w.showTech ? "\(w.rssi) dBm" : nil,
                     help: "How strong the connection to your router is. Closer = better.")
                chip("Speed", w.speedWord.word, w.speedWord.color, w.showTech ? "\(Int(w.txRate)) Mbps" : nil,
                     help: "How fast your Mac and router can talk to each other. This is not your internet speed — use Diagnostics → Speed test for that.")
                chip("Interference", w.interference.word, w.interference.color, w.showTech ? "SNR \(w.snr) dB" : nil,
                     help: "How much other devices and nearby networks are drowning out your signal.")
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
                Button("Diagnose") { select(.diagnostics); openSections.insert("tools"); w.runDiagnostics() }.buttonStyle(Pill())
            }.padding(10).background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        } else if w.status == .weak, w.betterOption == nil {
            HStack {
                Image(systemName: "wifi").foregroundStyle(.orange)
                Text("Weak signal. A stronger network may be nearby.").font(.caption)
            }.padding(10).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: public network advisory
    @ViewBuilder var publicCard: some View {
        if w.onPublicNetwork, w.warnPublic, let s = w.ssid, !w.mutedPublic.contains(s) {
            if let node = w.vpn.exitNode {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.good)
                    Text("**Protected** · Tailscale exit node \(node)").font(.caption)
                    Spacer(minLength: 0)
                }.padding(10).background(Theme.good.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.shield").font(.system(size: 20)).foregroundStyle(Theme.warn)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("This is a public network").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.warn)
                            Text("Other people on it may see unencrypted traffic, and the sign-in page can log your device. A VPN keeps your browsing private.")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    vpnRow
                    HStack {
                        Spacer()
                        Button("Don't warn me here") { w.muteWarning(s) }.buttonStyle(.plain)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.warn.opacity(0.35), lineWidth: 1))
            }
        }
    }

    @ViewBuilder var vpnRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "network.badge.shield.half.filled").font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(width: 28, height: 28).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            if !w.vpn.installed {
                VStack(alignment: .leading, spacing: 1) {
                    Text("No VPN found").font(.system(size: 12, weight: .semibold))
                    Text("Tailscale is a free option").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Get Tailscale") { NSWorkspace.shared.open(URL(string: "https://tailscale.com/download")!) }
                    .buttonStyle(Pill(fill: Theme.accent, fg: .black))
            } else if !w.vpn.running {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tailscale is off").font(.system(size: 12, weight: .semibold))
                    Text("Turn it on to protect this connection").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Turn on") { w.enableVPN() }.buttonStyle(Pill(fill: Theme.accent, fg: .black))
            } else if let opt = w.vpn.exitOption, let ip = w.vpn.exitOptionIP {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tailscale is on").font(.system(size: 12, weight: .semibold))
                    Text("Exit node available: \(opt)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use \(opt)") { w.useExitNode(ip) }.buttonStyle(Pill(fill: Theme.accent, fg: .black))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tailscale is on").font(.system(size: 12, weight: .semibold))
                    Text("No exit node set up, so web traffic still uses this network").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(10).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Button("Check for Updates…") { checkForUpdatesAction?() }
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
    @ViewBuilder var networkList: some View {
        if listOpenNow { fullList } else { collapsedList }
    }

    var updatedAgo: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let s = w.lastScanned.map { Int(ctx.date.timeIntervalSince($0)) }
            HStack(spacing: 5) {
                Circle().fill(Theme.good).frame(width: 6, height: 6)
                Text(s == nil ? "Scanning…" : s! < 5 ? "Live · just now" : s! < 60 ? "Live · \(s!)s ago" : "Live · \(s! / 60)m ago")
            }
        }
    }

    /// Only the network you're on, with the rest a tap away.
    var collapsedList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cur = w.sortedNetworks.first(where: { $0.ssid == w.ssid }) { row(cur) }
            Button { listOpen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Text("Other networks · \(max(0, w.networks.count - (w.networks.contains { $0.ssid == w.ssid } ? 1 : 0)))")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    updatedAgo.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    var fullList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if w.healthy {
                    Button { listOpen = false } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            Text("\(w.networks.count) networks").font(.caption)
                        }
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("Hide the other networks")
                } else {
                    Text("\(w.networks.count) networks").font(.caption).foregroundStyle(.secondary)
                }
                updatedAgo.font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if w.scanning { ProgressView().controlSize(.small) }
                else { Button { Task { await w.scan() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless) }
            }
            ScrollView { VStack(spacing: 0) { ForEach(w.sortedNetworks) { row($0) } } }
        }
    }

    func row(_ n: Net) -> some View {
        let isCurrent = n.ssid == w.ssid
        let fav = w.favorites.contains(n.ssid)
        let saved = w.isSaved(n.ssid)
        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button { w.toggleFavorite(n.ssid) } label: {
                    Image(systemName: fav ? "star.fill" : "star").font(.system(size: 11))
                        .foregroundStyle(fav ? Theme.warn : Color.secondary.opacity(0.7))
                }.buttonStyle(.plain).help("Favorite — used by smart auto-connect")
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.ssid).font(.system(size: 12, weight: isCurrent ? .semibold : .medium)).lineLimit(1)
                    Text(meta(n, isCurrent)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        .help("\(n.band): \(WiFiManager.bandHint(n.band)). Signal: \(WiFiManager.quality(rssi: n.rssi).word).")
                }
                Spacer()
                if w.connecting == n.ssid { ProgressView().controlSize(.small) }
                if n.secure { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
                else { Image(systemName: "exclamationmark.shield").font(.system(size: 11)).foregroundStyle(Theme.warn).help("Public network") }
                Button { w.toggleSaved(n.ssid) } label: {
                    FloppyIcon(filled: saved, color: saved ? Theme.accent : Color.secondary.opacity(0.8)).frame(width: 13, height: 13)
                }.buttonStyle(.plain)
                    .help(saved ? "Saved. Click to forget it after \(w.expiryDays) days of not using it" : "Not saved. Click to keep it until you remove it")
                if isCurrent { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent) }
                SignalBars(rssi: n.rssi)
            }
            .padding(.horizontal, 10).frame(height: 38)
            .background(isCurrent ? Theme.accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isCurrent else { return }
                if n.secure && !n.known { pwFor = n.ssid; pw = "" }
                else { Task { await w.connect(n, password: nil) } }
            }
            .contextMenu { if n.known || saved { Button("Forget Network") { w.forget(n.ssid) } } }
            if pwFor == n.ssid || w.needsPassword == n.ssid {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SecureField("Password", text: $pw).textFieldStyle(.roundedBorder).onSubmit { submit(n) }
                        Button("Join") { submit(n) }.buttonStyle(Pill(fill: Theme.accent, fg: .black)).disabled(pw.isEmpty)
                    }
                    HStack(spacing: 5) {
                        FloppyIcon(filled: saved, color: saved ? Theme.accent : .secondary).frame(width: 11, height: 11)
                        Text(saved ? "Saved in your Keychain. Tap the icon to forget it after \(w.expiryDays) days instead."
                                   : "Forgotten after \(w.expiryDays) days. Tap the icon to keep it.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.horizontal, 10).padding(.bottom, 4)
            }
        }
    }

    func meta(_ n: Net, _ current: Bool) -> String {
        var parts: [String] = []
        if current { parts.append("Connected") }
        else if w.favorites.contains(n.ssid) { parts.append("Favorite") }
        else if w.isSaved(n.ssid) { parts.append("Saved") }
        else if let d = w.daysLeft(n.ssid) { parts.append(d == 0 ? "Forgets today" : "Forgets in \(d)d") }
        else if n.known { parts.append("Known") }
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

    // MARK: diagnostics tab (live link, nearby channels, speed test, tools)
    var diagnostics: some View {
        ScrollView {
            VStack(spacing: 8) {
                section("live", "Your connection, live", "Last \(max(1, w.samples.count * 4 / 60)) min") { liveBody }
                section("nearby", "Nearby channels", "\(w.aps.count) nearby") { signalsBody }
                speedCard
                section("tools", "Tools", "Check, reconnect") { diagBody }
            }
        }
    }

    func section<C: View>(_ key: String, _ title: String, _ trailing: String = "", @ViewBuilder _ content: () -> C) -> some View {
        let open = openSections.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if open { openSections.remove(key) } else { openSections.insert(key) }
                }
            } label: {
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if !trailing.isEmpty && !open { Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary) }
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open { content() }
        }
        .card(12)
    }

    var signalsBody: some View {
        let bands = w.bandsPresent
        let b = bands.contains(band) ? band : (bands.contains(w.bandName) ? w.bandName : (bands.first ?? "5 GHz"))
        let (loads, rec) = w.channelLoads(band: b)
        return VStack(alignment: .leading, spacing: 6) {
            if bands.count > 1 {
                Picker("", selection: $band) { ForEach(bands, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
            }
            Chart(loads) { c in
                BarMark(x: .value("Channel", String(c.ch)), y: .value("Load", c.load))
                    .foregroundStyle(c.kind == 1 ? Color.blue : c.kind == 2 ? Color.green : Color.gray.opacity(0.5))
            }
            .chartYAxis(.hidden).frame(height: 60)
            if let rec {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    Text(rec == w.channelNum && b == w.bandName ? "You're already on the clearest channel."
                         : "Set your router to channel \(rec) for less interference.").font(.caption)
                }
            }
            VStack(spacing: 0) {
                ForEach(w.aps.prefix(6)) { ap in
                    HStack(spacing: 6) {
                        Text(ap.ssid).lineLimit(1).font(.caption)
                            .fontWeight(ap.ssid == w.ssid ? .semibold : .regular)
                        Spacer()
                        Text("Ch \(ap.channel)").font(.caption2).foregroundStyle(.secondary)
                        Text(ap.band).font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: max(0, min(1, Double(ap.rssi + 95) / 55)))
                            .frame(width: 44).tint(ap.rssi > -60 ? .green : ap.rssi > -75 ? .orange : .red)
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    var liveBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if w.samples.count < 2 {
                Text(w.ssid == nil ? "Connect to a network to see live data." : "Collecting samples…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if let st = w.stability { HStack(spacing: 6) { Circle().fill(st.color).frame(width: 7, height: 7); Text(st.text).font(.caption.weight(.medium)) } }
                Text("Signal strength — higher is better").font(.system(size: 11)).foregroundStyle(.secondary)
                Chart(w.samples) { s in
                    LineMark(x: .value("t", s.t), y: .value("dBm", s.rssi)).foregroundStyle(.blue)
                    AreaMark(x: .value("t", s.t), yStart: .value("floor", -95), yEnd: .value("dBm", s.rssi)).foregroundStyle(.blue.opacity(0.12))
                }
                .chartYScale(domain: -95 ... -30).frame(height: 70)
                let lat = w.samples.compactMap(\.latency)
                HStack {
                    Text("Response time — lower is better").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !lat.isEmpty {
                        Text(String(format: "typically %.0f ms", lat.reduce(0, +) / Double(lat.count)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Chart(w.samples.filter { $0.latency != nil }) { s in
                    LineMark(x: .value("t", s.t), y: .value("ms", s.latency ?? 0)).foregroundStyle(.purple)
                }.frame(height: 70)
            }
        }
    }

    func stat(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.system(.caption, design: .monospaced))
        }
    }

    var speedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed test").font(.system(size: 12, weight: .semibold))
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

    var diagBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Find out what's wrong").font(.system(size: 11)).foregroundStyle(.secondary)
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

/// Lays chips out left to right and wraps onto a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let a = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in a.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var pts: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += s.width + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), pts)
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
