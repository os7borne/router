# Router

A fast, friendly Wi-Fi control for the macOS menubar. Router replaces the clunky native Wi-Fi menu with one that explains things in plain language.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9-orange) ![license](https://img.shields.io/badge/license-MIT-green)

## Features
- **Switch networks quickly**, with favourites and smart auto-connect that roams to a starred network when the signal drops.
- **Plain-language status.** No signal-engineering degree needed. Technical numbers are optional.
- **Speed test and diagnostics** (gateway, DNS, latency, internet reachability).
- **Live graphs, nearby signals and channel congestion.**
- **Captive-portal detection** with a one-click "Sign in".
- **State-coloured menubar icon:** connected, disconnected, hotspot, weak signal, login required, no internet.
- **Notifications** for connection changes, and a global hotkey (`⌃⌥W`).
- **Places.** Optionally tracks time spent at each location (Wi-Fi network plus GPS), with per-place speed history and day/week/month/year/all-time analytics in a detailed window.

## Download
Grab the latest `Router.zip` from the [Releases](../../releases) page, unzip, and drag **Router.app** to `/Applications`. Releases are signed and notarized, and Router updates itself after that (gear menu → **Check for Updates…**).

## Requirements
- macOS 13 or later
- Swift 5.9+ toolchain (Xcode or Command Line Tools)

## Build and install
```sh
git clone https://github.com/os7borne/router.git router
cd router
./build.sh            # builds build/Router.app
./build.sh install    # also copies it to /Applications
open build/Router.app
```

### Code signing
macOS ties the Location permission to the app's code signature. `build.sh` signs with a Developer ID Application identity if you have one, then an Apple Development identity, then falls back to ad-hoc. Override with:
```sh
SIGN_ID="Your Identity Name" ./build.sh
```
With ad-hoc signing the signature changes on every build, so macOS asks for Location again each time. A stable identity avoids this.

## Permissions
- **Location** is required for macOS to reveal Wi-Fi network names (SSIDs), and for the Places feature. Router asks once. You can check or change it in Settings → Privacy.
- **Notifications** are optional.

## Privacy
Everything stays on your Mac. Router has no accounts, analytics or servers.
- Place history is stored in `~/Library/Application Support/Router/router.sqlite` (unencrypted).
- The only network requests are `captive.apple.com` (login-page check), Apple's `networkQuality` speed test when you run it, and Apple's reverse-geocoding service to name places.
- Delete your data any time: Settings → Places → Delete…, "Forget place", or remove the folder above.

## Project layout
```
Sources/Router/   App source (SwiftUI + AppKit, CoreWLAN, CoreLocation, SQLite)
tools/            Icon generator
build.sh          Build, sign, install script
agent.md          Detailed architecture notes and handoff context
```
See [agent.md](agent.md) for architecture, design decisions and known issues.

## Contributing
Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) first. Report security problems as described in [SECURITY.md](SECURITY.md).

## License
[MIT](LICENSE)

## Releasing
Releases are built on the maintainer's Mac, because signing and update keys live in its Keychain.
1. Update the version in `Info.plist` (`CFBundleShortVersionString`, and raise `CFBundleVersion`, which Sparkle compares).
2. Move the "Unreleased" notes in `CHANGELOG.md` under the new version and write `notes/<version>.md` (shown in the update window).
3. Commit and push.
4. `./build.sh release` (Developer ID signed, notarized, stapled; needs `release.local.env`) then `tools/make-appcast.sh`.
5. `gh release create v<version> dist/Router.zip dist/appcast.xml --title "Router <version>" --notes-file notes/<version>.md`.
The app reads its update feed from `releases/latest/download/appcast.xml`.
