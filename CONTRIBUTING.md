# Contributing to Router

Thanks for helping. Small, focused changes are easiest to review.

## Getting started
1. Fork and clone the repo.
2. `./build.sh` to build, then `open build/Router.app`.
3. Read [agent.md](agent.md) for the architecture and the decisions already made.

## Ground rules
- **Plain language.** UI text should make sense to someone with no networking background. Put technical detail behind "Show technical details".
- **Privacy first.** No analytics, tracking or new network calls without a clear reason and a note in the README.
- **Keep the look.** The app icon and 16 pt menubar icon are intentional. Propose changes in an issue first.
- Match the existing style. Keep views small and put logic in `WiFiManager` / `PlaceTracker`, not views.
- Mind main-actor isolation. State types are `@MainActor`.
- Check your UI at both light and dark appearance, and watch for text wrapping in the 380 pt popover.

## Submitting changes
1. Create a branch: `git checkout -b feature/short-name`.
2. Make sure `swift build -c release` succeeds with no new warnings.
3. Describe what changed and why in the pull request, with a screenshot for UI changes.
4. Update [CHANGELOG.md](CHANGELOG.md) under "Unreleased".

## Reporting bugs
Open an issue using the bug template. Include your macOS version, what you expected, what happened, and any error text shown in the app.

## Testing notes
Wi-Fi behaviour depends on real hardware and networks, so most checks are manual. Useful scenarios: switch away from and back to a saved network, join a hotspot, join a captive-portal network, toggle Wi-Fi off, and put the Mac to sleep and wake it.
