# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.2.2] - 2026-11-19
- Optional switch (Settings → Connection) to replace the macOS sign-in window with Router's own, which opens automatically and can fill in saved details.
- The public-network warning shows right after launch, using the networks the last scan found open.
- New "Test sign-in window" item in the gear menu.

## [0.2.1] - 2026-11-17
- The public-network warning is now one slim row, with a single button that fits the current Tailscale state.
- Diagnostics sections work as an accordion: one open at a time, with short summaries when collapsed.
- Switching tabs swipes the old content out and the new content in, and the popover's content no longer drifts while it resizes.
- The connected network's detail line is no longer cut off.

## [0.2.0] - 2026-11-17
- Automatic updates through Sparkle. Check from the gear menu or Settings → Updates.
- Simpler popup: the status card and network list collapse while the connection is good, and open when it isn't.
- Signals, Live and Tools are merged into one Diagnostics tab.
- Use-case ratings: Browsing, Video calls, Streaming, Gaming and Downloads.
- Save icon on every network. Unsaved networks are forgotten after a set number of days.
- Public-network warning with Tailscale controls.
- Sign-in window for captive portals that fills saved details and stops at one-time codes.
- The list of networks refreshes in the background, with the connected network always on top.

## [0.1.0] - 2026-11-15

### Changed
- Places are now named by location (area, then city) instead of Wi-Fi network name. The network shows as secondary text ("via surihome"). Renaming a place still overrides the name.

### Added
- Swipe left/right (trackpad) to move between popover panels.
- Readable time-chart axes (weekdays, hours, day numbers, months; "1h 30m" labels).
- "Mini project by" credit line and a Send feedback option in Settings.
- Menubar Wi-Fi control: switch networks, favourites, smart auto-connect.
- Plain-language status, speed test, diagnostics, live graphs, nearby signals, channel congestion.
- Captive-portal detection, state-coloured menubar icon, notifications, global hotkey (`⌃⌥W`).
- Settings window with Location access row and launch at login.
- Places: time tracking by location (network + GPS), reverse-geocoded area/city, per-place speed history.
- Compact Places summary in the popover and a detailed Analytics window (day/week/month/year/all-time).

[Unreleased]: ../../compare/v0.1.0...HEAD
[0.1.0]: ../../releases/tag/v0.1.0
