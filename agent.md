# Router: agent handoff

Native macOS menubar Wi-Fi control app. This file gives the next session everything needed to take over.

## What it is
A faster, friendlier replacement for the native Wi-Fi menu. It lets you:
- switch networks
- auto-connect (smart roam to favourites)
- run speed tests and diagnostics
- see live graphs, nearby signals and channel congestion
- detect captive portals ("login required")
- use a global hotkey (⌃⌥W)
- get notifications and a state-coloured menubar icon
- track time at places (Places feature)

All text is written in plain, non-technical language. Technical numbers are optional, behind "Show technical details".

## Stack
- SwiftPM executable. swift-tools-version 5.9, macOS 13+, Swift 5 language mode.
- SwiftUI and AppKit. Entry is pure AppKit in `Sources/Router/main.swift` (there is no SwiftUI `App` scene). It uses `MainActor.assumeIsolated`, sets `.accessory` activation policy, and runs `NSApplication`.
- Frameworks: CoreWLAN, CoreLocation (including `CLGeocoder`), Swift Charts, SQLite3 C API, UserNotifications, Carbon (`RegisterEventHotKey`), ServiceManagement (`SMAppService`), `os.Logger`.
- Bundle id `local.router.menubar`. `LSUIElement` is true.

## Build and run
```
cd /Library/WebServer/Documents/projects/custom-ext/router
./build.sh            # swift build -c release, then assembles build/Router.app
./build.sh install    # also copies to /Applications
open build/Router.app
```
- `build.sh` generates the icon (`swift tools/make-icon.swift`, then `iconutil`).
- It signs with the Developer ID Application identity (`SIGN_ID` env override), falling back to Apple Development, then ad-hoc.
- **Signing matters.** Location permission (TCC) is tied to the code signature. Ad-hoc builds change cdhash every build, so the permission resets. Keep the stable identity.
- Quit the running app before rebuilding or reinstalling (`pkill Router`).

## File map (`Sources/Router/`)
| File | Role |
|---|---|
| `main.swift` | AppKit entry point |
| `RouterApp.swift` | `AppDelegate`: NSStatusItem, NSPopover (transient, plus global/local mouse monitors to close on outside click), `updateIcon()` (16 pt SF Symbols; template for normal states, tinted for hotspot/weak/login/no-internet), Carbon hotkey, `showSettings()`, `showAnalytics(_:)`. Globals: `hotkeyAction`, `openSettingsAction`, `openAnalyticsAction`. |
| `WiFiManager.swift` | `@MainActor` singleton `WiFiManager.shared`. Holds all Wi-Fi state, a 4 s `tick()`, scan/connect/forget/power, smart roam, weak-signal hysteresis (<-75 on, >-68 off), notifications, diagnostics, speed test, location access, launch at login. Owns `tracker = PlaceTracker()`. |
| `Diagnostics.swift` | Shell helpers (gateway, ping, dns, captive check, latency), `DiagStep`, `Sample`, `AP`, `ChanLoad`, `Status` enum |
| `Plain.swift` | Plain-language layer: Quality, headline, advice, better-option, stability, speed verdicts, band hints |
| `Theme.swift` | Gradients, colours, `.card()` modifier, `SignalBars`, `AppMark`, `Pill` button style, chart series palette |
| `ContentView.swift` | Popover UI, 380 pt wide. Tabs: Networks, Signals, Live, Places, Tools. |
| `SettingsView.swift` | Settings window, fixed 500×560 inside a `ScrollView` |
| `Store.swift` | SQLite wrapper (tables `places`, `sessions`, `samples`; WAL) |
| `PlaceTracker.swift` | Places engine: sessions, place matching, geocoding, reports/analytics queries |
| `PlacesView.swift` | Compact Places tab in the popover |
| `AnalyticsView.swift` | Detailed Analytics window (KPIs, stacked time chart, weekday×hour heatmap, download-by-place chart, sortable places table, place detail card, sessions log) |

Other files:
- `Info.plist` (location usage strings, `CFBundleIconFile`)
- `Package.swift`
- `build.sh`
- `tools/make-icon.swift`

## Key behaviours and decisions
- **Diagnostics tools:**
  - Speed test: `networkQuality -c`.
  - Gateway: `route -n get default`.
  - Latency: `ping`.
  - Captive portal: `curl captive.apple.com/hotspot-detect.html` (the body must contain "Success").
- **Hotspot detection:** gateway `172.20.10.*` or `192.168.43.*`, or the SSID contains iphone/android/hotspot.
- **SSIDs are redacted without Location authorization.** The Settings → Privacy row shows Location state and has a button. It calls `requestAlwaysAuthorization` if undetermined, otherwise it opens System Settings.
- **Connect flow:** fresh `scanForNetworks(withSSID:)`, then associate. On failure it sets `needsPassword` or `error` and logs. The UI shows a password field and a dismissable error banner.
- **Popover:** after showing it, call `makeKey()` so controls render active, not grey.
- **Menubar icon:** 16 pt. The user asked for this twice; do not change it.
- **Logo:** the user said **leave the logo as is** (the blue→cyan squircle with three white Wi-Fi arcs and a dot). Do not redesign it.
- **Settings window:** fixed height with scrolling. Rows are label-left, control-right, with dividers.

### Places feature
- **Data location:** `~/Library/Application Support/Router/router.sqlite` (plus `-wal` and `-shm`). It is local only and unencrypted.
- **Persistence:** quitting or rebuilding does NOT delete data. It is removed only by Settings → Places → Delete…, "Forget place", or manual file deletion.
- **Place matching:**
  1. Use the nearest place within the radius (default 150 m, 50–500 m in Settings).
  2. Otherwise use the same SSID within max(2r, 300 m).
  3. Otherwise create a new place.
  4. Hotspot sessions match by coordinates only.
- **Session ends** on sleep, a gap over 45 s, an SSID change, or pause.
- **Location and geocoding:** location is requested every 600 s. Reverse geocoding (Apple `CLGeocoder`) runs every 30 s, once per place, and fills area/city.
- **Speed history:** speed tests record a "speed" sample against the current place.
- **Popover Places tab:** simple. It has a Day/Week/Month/Year picker, total time, a small chart, the top 3 places, "+N more", and a "View details" button.
- **Analytics window:** 1000×720, min 860×600. It adds an All period, a Places/Cities toggle, prev/next navigation, and `wifi.tracker.focusPlace` for deep-linking a place.
- **Limits:** only counts time the Mac is awake and connected. Accuracy is about 50–100 m. Data is sparse at first.

## Design canvas (visual reference only)
Boards are in the session scratchpad `…/scratchpad/canvas/project/` (Main, Tools, Settings, Logo, Menubar, Logos `.dc.html` plus `canvas.json`). They were published as a private artifact: https://claude.ai/artifact/6uxXwyCTTpZmMPriyiLYNv. The scratchpad can be cleared, so treat the Swift code as the source of truth.

## History of bugs already fixed (don't regress)
- Blank or double Settings window: caused by a leftover SwiftUI `Settings { EmptyView() }` scene. Fixed by the AppKit entry point and a real `SettingsView`.
- Misaligned Settings layout: rebuilt with fixed HStack rows.
- Chips and rows wrapping: single-line chips (`lineLimit(1).fixedSize()`).
- Grey switches: `makeKey()` after showing the popover.
- Slider binding on a `let` tracker: use `Binding(get:set:)`.
- Popover not closing on outside click: NSEvent monitors plus resign-active.
- Location permission resetting each rebuild: Developer ID signing.

## Open and unconfirmed items
1. **Reconnect to a favourite network** (the user reported that switching away and back failed, seen with an "Oz-Droid" hotspot). A fresh targeted scan, a password prompt, an error banner and logging were added. It is unconfirmed whether this fixes it. Ask the user for the banner text, or check logs (`log show --predicate 'subsystem == "local.router.menubar"'`, adjust to the Logger subsystem in the code).
2. **Location persistence across rebuilds:** the user must re-grant once. Verify it survives the next rebuild with the Developer ID signature.
3. **Places tab and Analytics window have never been visually verified** (no screenshots were taken by choice).
4. **Not built (not requested):** CSV export, per-place favourites or alerts, DB encryption.

## Working agreements with this user
- Do not take full-screen screenshots or send keystrokes (e.g. ⌃⌥W) to the system. An earlier capture exposed private browser content and the keystroke went to the frontmost app. Ask first, or have the user supply screenshots.
- Foreground `sleep` is blocked in the harness; use a `timeout … until` loop instead.
- The user prefers plain, non-technical UI language and tight, uncluttered layouts. They have been blunt about visual problems ("looks hideous"), so check alignment and wrapping.
- When you run the app, quit the old instance first and tell the user if they must re-grant Location.
