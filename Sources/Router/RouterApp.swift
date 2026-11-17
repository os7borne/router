import SwiftUI
import AppKit
import Carbon
import Combine
import UserNotifications
import Sparkle

nonisolated(unsafe) var hotkeyAction: (() -> Void)?
nonisolated(unsafe) var openSettingsAction: (() -> Void)?
nonisolated(unsafe) var updaterController: SPUStandardUpdaterController?
nonisolated(unsafe) var checkForUpdatesAction: (() -> Void)?
nonisolated(unsafe) var openAnalyticsAction: ((Int64?) -> Void)?

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    let wifi = WiFiManager.shared
    var settingsWindow: NSWindow?
    var analyticsWindow: NSWindow?
    var item: NSStatusItem!
    let popover = NSPopover()
    var bag = Set<AnyCancellable>()
    var lastKey = ""
    var hotKeyRef: EventHotKeyRef?
    var globalClick: Any?
    var localClick: Any?

    func applicationDidFinishLaunching(_ n: Notification) {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        checkForUpdatesAction = { [weak self] in
            self?.popover.performClose(nil)
            NSApp.activate(ignoringOtherApps: true)
            updaterController?.checkForUpdates(nil)
        }
        UNUserNotificationCenter.current().delegate = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)

        let host = NSHostingController(rootView: ContentView().environmentObject(wifi))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }

        wifi.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateIcon() }.store(in: &bag)
        updateIcon()
        registerHotkey()
        openSettingsAction = { [weak self] in self?.showSettings() }
        openAnalyticsAction = { [weak self] id in self?.showAnalytics(id) }
    }

    func showAnalytics(_ placeId: Int64?) {
        popover.performClose(nil)
        wifi.tracker.focusPlace = placeId
        if analyticsWindow == nil {
            let host = NSHostingController(rootView: AnalyticsView(t: wifi.tracker))
            let w = NSWindow(contentViewController: host)
            w.title = "Router — Places Analytics"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 1000, height: 720))
            w.minSize = NSSize(width: 860, height: 600)
            w.center()
            analyticsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        analyticsWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(wifi)))
            w.title = "Router Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        wifi.menuOpen = false
        if let g = globalClick { NSEvent.removeMonitor(g); globalClick = nil }
        if let l = localClick { NSEvent.removeMonitor(l); localClick = nil }
    }

    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                            withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }

    @objc func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item.button else { return }
        wifi.onOpen()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Close when the user clicks anywhere outside the popover (other apps, desktop, our own other windows).
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            MainActor.assumeIsolated {
                if let self, self.popover.isShown, e.window !== self.popover.contentViewController?.view.window,
                   e.window !== self.item.button?.window { self.popover.performClose(nil) }
            }
            return e
        }
    }

    /// Global hotkey: ⌃⌥W
    func registerHotkey() {
        hotkeyAction = { [weak self] in Task { @MainActor in self?.toggle() } }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in hotkeyAction?(); return noErr }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x52545231), id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func updateIcon() {
        let s = wifi.status
        let bars: Double = {
            switch wifi.rssi { case ..<(-80): return 0.25; case ..<(-70): return 0.5; case ..<(-60): return 0.75; default: return 1 }
        }()
        let key = "\(s.rawValue)-\(bars)"
        guard key != lastKey else { return }
        lastKey = key

        var name = "wifi"; var value: Double? = nil; var color: NSColor? = nil
        switch s {
        case .off: name = "wifi.slash"
        case .disconnected: value = 0
        case .connected: value = bars
        case .hotspot: name = "personalhotspot"; color = .systemGreen
        case .weak: value = bars; color = .systemOrange
        case .loginRequired: name = "lock.shield"; color = .systemOrange
        case .noInternet: name = "wifi.exclamationmark"; color = .systemRed
        }
        let img: NSImage?
        if let v = value { img = NSImage(systemSymbolName: name, variableValue: v, accessibilityDescription: s.rawValue) }
        else { img = NSImage(systemSymbolName: name, accessibilityDescription: s.rawValue) }
        let size = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let c = color, let tinted = img?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [c]).applying(size)) {
            tinted.isTemplate = false
            item.button?.image = tinted
        } else {
            let big = img?.withSymbolConfiguration(size)
            big?.isTemplate = true
            item.button?.image = big
        }
    }
}
