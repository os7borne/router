import SwiftUI
import WebKit
import AppKit

/// Router's own sign-in window for captive portals. It shows the venue's real page, fills in
/// details saved for this network, and stops at one-time-code fields so the user can finish.
@MainActor
final class PortalController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = PortalController()

    enum Step { case filling, yourTurn, online }
    @Published var step: Step = .filling
    @Published var filledCount = 0
    @Published var saveDetails = true

    let web: WKWebView
    private var window: NSWindow?
    private weak var wifi: WiFiManager?
    private var ssid = ""
    private var pollTimer: Timer?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()      // nothing from the portal lingers on disk
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        cfg.userContentController.add(self, name: "router")
        web.navigationDelegate = self
    }

    /// Builds the window and starts the web content process at launch so opening is instant.
    func prepare(wifi: WiFiManager) {
        self.wifi = wifi
        _ = makeWindow(wifi)
        web.loadHTMLString("", baseURL: nil)   // spins up the WebContent process
    }

    private func makeWindow(_ wifi: WiFiManager) -> NSWindow {
        if let w = window { return w }
        let w = NSPanel(contentViewController: NSHostingController(rootView: PortalView(c: self).environmentObject(wifi)))
        w.title = "Sign in"
        w.styleMask = [.titled, .closable, .resizable, .utilityWindow]
        w.setContentSize(NSSize(width: 460, height: 680))
        w.isReleasedWhenClosed = false
        // Like macOS's own sign-in window: above other apps' windows, on every Space, even over full screen.
        w.level = .floating
        w.isFloatingPanel = true
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window = w
        return w
    }

    func open(wifi: WiFiManager) {
        self.wifi = wifi
        ssid = wifi.ssid ?? ""
        step = .filling; filledCount = 0
        let w = makeWindow(wifi)
        w.title = ssid.isEmpty ? "Sign in" : "\(ssid) · Sign in"
        web.load(URLRequest(url: wifi.portalURL ?? URL(string: "http://captive.apple.com")!))
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkOnline() }
        }
    }

    private func checkOnline() {
        guard let w = wifi, window?.isVisible == true else { pollTimer?.invalidate(); return }
        w.recheckReach()
        if w.online && w.status != .loginRequired {
            step = .online
            pollTimer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.window?.close() }
        }
    }

    func forgetDetails() { PortalStore.remove(ssid); filledCount = 0 }
    var hasSavedDetails: Bool { PortalStore.get(ssid) != nil }

    // MARK: page scripting
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.inject() }
    }

    private func inject() {
        let host = web.url?.host ?? ""
        var profileJSON = "null"
        if let p = PortalStore.get(ssid), p.host == host,
           let d = try? JSONEncoder().encode(p.fields), let s = String(data: d, encoding: .utf8) {
            profileJSON = s
        }
        web.evaluateJavaScript(Self.script.replacingOccurrences(of: "__PROFILE__", with: profileJSON)) { _, _ in }
    }

    nonisolated func userContentController(_ ucc: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let body = m.body as? [String: Any], let type = body["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "state":
                self.filledCount = body["filled"] as? Int ?? 0
                if (body["needsCode"] as? Bool) == true { self.step = .yourTurn }
            case "learn":
                guard self.saveDetails, let host = body["host"] as? String,
                      let fields = body["fields"] as? [String: String], !fields.isEmpty else { return }
                var merged = PortalStore.get(self.ssid)?.fields ?? [:]
                if PortalStore.get(self.ssid)?.host != host { merged = [:] }
                merged.merge(fields) { _, new in new }
                PortalStore.set(self.ssid, PortalProfile(host: host, fields: merged))
            default: break
            }
        }
    }

    /// Fills known fields, never touches one-time-code inputs, and remembers what the user submits.
    static let script = #"""
    (function () {
      var profile = __PROFILE__;
      var SKIP = ['hidden','submit','button','image','reset','file'];
      function attr(e, n) { return (e.getAttribute(n) || '').toLowerCase(); }
      function isCode(e) {
        var t = (e.name + ' ' + e.id + ' ' + attr(e,'placeholder') + ' ' + attr(e,'aria-label')).toLowerCase();
        if (attr(e,'autocomplete') === 'one-time-code') return true;
        if (/zip|post|country|area|promo|coupon|voucher/.test(t)) return false;
        return /otp|one.?time|verif|sms|\bpin\b|\bcode\b|passcode/.test(t);
      }
      function key(e) {
        var n = (e.name || e.id || attr(e,'placeholder') || attr(e,'aria-label') || '').toLowerCase().replace(/[^a-z0-9]/g, '');
        return n + ':' + (e.type || 'text');
      }
      function fields() {
        return Array.prototype.slice.call(document.querySelectorAll('input, select, textarea'))
          .filter(function (e) { return SKIP.indexOf(e.type) < 0; });
      }
      function setValue(e, v) {
        var proto = e.tagName === 'SELECT' ? HTMLSelectElement.prototype : e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        var d = Object.getOwnPropertyDescriptor(proto, 'value');
        if (d && d.set) d.set.call(e, v); else e.value = v;
        e.dispatchEvent(new Event('input', { bubbles: true }));
        e.dispatchEvent(new Event('change', { bubbles: true }));
      }
      function setChecked(e, on) {
        if (e.checked !== on) e.click();
      }
      var filled = 0, code = null;
      fields().forEach(function (e) {
        if (isCode(e)) { if (!code) code = e; return; }
        if (!profile) return;
        var v = profile[key(e)];
        if (v === undefined) return;
        if (e.type === 'checkbox') { setChecked(e, v === 'on'); filled++; }
        else if (e.type === 'radio') { if (e.value === v) { setChecked(e, true); filled++; } }
        else if (!e.value) { setValue(e, v); filled++; }
      });
      if (code) { try { code.focus(); } catch (x) {} }
      window.webkit.messageHandlers.router.postMessage({ type: 'state', filled: filled, needsCode: !!code });

      if (window.__routerHooked) return;
      window.__routerHooked = true;
      function learn() {
        var out = {}, n = 0;
        fields().forEach(function (e) {
          if (isCode(e)) return;
          var k = key(e);
          if (e.type === 'checkbox') { out[k] = e.checked ? 'on' : 'off'; n++; }
          else if (e.type === 'radio') { if (e.checked) { out[k] = e.value; n++; } }
          else if (e.value) { out[k] = e.value; n++; }
        });
        if (n) window.webkit.messageHandlers.router.postMessage({ type: 'learn', host: location.host, fields: out });
      }
      document.addEventListener('submit', learn, true);
      document.addEventListener('click', function (ev) {
        var t = ev.target && ev.target.closest ? ev.target.closest('button, input[type=submit], input[type=button], a') : null;
        if (t) learn();
      }, true);
    })();
    """#
}

struct PortalView: View {
    @ObservedObject var c: PortalController
    @EnvironmentObject var w: WiFiManager

    var body: some View {
        VStack(spacing: 0) {
            strip
            Divider()
            PortalWeb(web: c.web)
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    var strip: some View {
        HStack(spacing: 0) {
            stepDot("Details filled", state: c.step == .filling ? (c.filledCount > 0 ? .done : .active) : .done)
            line
            stepDot(c.step == .yourTurn ? "Your turn: enter the code" : "Sign in", state: c.step == .online ? .done : (c.step == .yourTurn ? .active : .idle), number: "2")
            line
            stepDot("Online", state: c.step == .online ? .done : .idle)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    enum DotState { case idle, active, done }
    func stepDot(_ t: String, state: DotState, number: String = "") -> some View {
        let col: Color = state == .done ? Theme.good : state == .active ? Theme.accent : Color.secondary
        return HStack(spacing: 6) {
            ZStack {
                Circle().stroke(state == .idle ? Color.secondary.opacity(0.5) : col, lineWidth: 1.5).frame(width: 16, height: 16)
                if state == .done { Circle().fill(col).frame(width: 16, height: 16); Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black) }
                if state == .active { Circle().fill(col).frame(width: 16, height: 16); Text(number).font(.system(size: 9, weight: .bold)).foregroundStyle(.black) }
            }
            Text(t).font(.system(size: 11, weight: state == .active ? .semibold : .regular)).foregroundStyle(col).lineLimit(1)
        }
    }
    var line: some View { Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1).padding(.horizontal, 8) }

    var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi").foregroundStyle(Theme.accent)
                Text(c.step == .online ? "You're online."
                     : c.filledCount > 0 ? "Router filled in your saved details. Codes change every time, so enter this one yourself. After that you're online."
                     : "Fill in this page once and Router will remember it for next time.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Button { w.toggleSaved(w.ssid ?? "") } label: {
                    HStack(spacing: 5) {
                        FloppyIcon(filled: w.isSaved(w.ssid ?? ""), color: w.isSaved(w.ssid ?? "") ? Theme.accent : .secondary).frame(width: 13, height: 13)
                        Text(w.isSaved(w.ssid ?? "") ? "Network saved" : "Save network").font(.system(size: 11))
                    }
                }.buttonStyle(.plain)
                Toggle("Save these details", isOn: $c.saveDetails).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                if c.hasSavedDetails { Button("Forget details") { c.forgetDetails() }.buttonStyle(.link).font(.system(size: 11)) }
            }
        }
        .padding(12)
    }
}

struct PortalWeb: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// The save icon: a floppy disk, outlined when not saved and filled when saved.
struct FloppyIcon: View {
    var filled: Bool
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24
            var outer = Path()
            outer.move(to: CGPoint(x: 5, y: 3)); outer.addLine(to: CGPoint(x: 16, y: 3)); outer.addLine(to: CGPoint(x: 20, y: 7))
            outer.addLine(to: CGPoint(x: 20, y: 19)); outer.addQuadCurve(to: CGPoint(x: 18, y: 21), control: CGPoint(x: 20, y: 21))
            outer.addLine(to: CGPoint(x: 5, y: 21)); outer.addQuadCurve(to: CGPoint(x: 3, y: 19), control: CGPoint(x: 3, y: 21))
            outer.addLine(to: CGPoint(x: 3, y: 5)); outer.addQuadCurve(to: CGPoint(x: 5, y: 3), control: CGPoint(x: 3, y: 3))
            outer.closeSubpath()
            var inner = Path()
            inner.move(to: CGPoint(x: 7, y: 3)); inner.addLine(to: CGPoint(x: 7, y: 8)); inner.addLine(to: CGPoint(x: 15, y: 8)); inner.addLine(to: CGPoint(x: 15, y: 3))
            inner.move(to: CGPoint(x: 7, y: 21)); inner.addLine(to: CGPoint(x: 7, y: 14)); inner.addLine(to: CGPoint(x: 17, y: 14)); inner.addLine(to: CGPoint(x: 17, y: 21))
            let t = CGAffineTransform(scaleX: s, y: s)
            let style = StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round)
            if filled { ctx.fill(outer.applying(t), with: .color(color)) }
            ctx.stroke(outer.applying(t), with: .color(color), style: style)
            ctx.stroke(inner.applying(t), with: .color(filled ? Color(nsColor: .windowBackgroundColor) : color), style: style)
        }
    }
}
