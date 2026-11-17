#!/bin/zsh
# Builds Router.app.
#   ./build.sh            dev build (signed with a local identity, or ad-hoc)
#   ./build.sh install    dev build, then replace /Applications/Router.app and open it
#   ./build.sh release    universal, Developer ID signed, notarized, stapled -> dist/Router.zip
# Release builds read IDENTITY, KEY_PATH, KEY_ID and ISSUER from the git-ignored release.local.env.
set -e
cd "$(dirname "$0")"
MODE=${1:-dev}
[[ -f release.local.env ]] && source ./release.local.env
APP=build/Router.app

if [[ "$MODE" == "release" ]]; then
  : "${IDENTITY:?set IDENTITY in release.local.env}"
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Router"
else
  swift build -c release
  BIN=.build/release/Router
fi

rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources $APP/Contents/Frameworks build/AppIcon.iconset
cp $BIN $APP/Contents/MacOS/Router
cp Info.plist $APP/Contents/Info.plist

# Sparkle (auto-update) ships inside the app. Router isn't sandboxed, so Sparkle's XPC helpers aren't needed.
SPK=$APP/Contents/Frameworks/Sparkle.framework
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $SPK
rm -rf $SPK/Versions/B/XPCServices $SPK/XPCServices
cp .build/artifacts/sparkle/Sparkle/LICENSE $APP/Contents/Resources/Sparkle-LICENSE.txt   # MIT: keep the notice with the binary

swift tools/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns

if [[ "$MODE" == "release" ]]; then
  # sign inside-out: Sparkle's helpers, then the framework, then the app
  for item in "$SPK/Versions/B/Autoupdate" "$SPK/Versions/B/Updater.app" "$SPK"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" $APP
  codesign --verify --strict --verbose=2 $APP
else
  # Sign with a stable identity so macOS keeps the Location permission across rebuilds
  # (ad-hoc signing changes the app's identity on every build and resets permissions).
  ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}
  if [[ -z "$ID" ]]; then ID=$(security find-identity -v -p codesigning | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"'); fi
  if [[ -n "$ID" ]]; then
    echo "Signing as: $ID"
    codesign --force --options runtime --sign "$ID" $SPK
    codesign --force --options runtime --sign "$ID" $APP
  else
    echo "No signing identity found, using ad-hoc (Location permission will reset each build)"
    codesign --force --deep --sign - $APP
  fi
fi
echo "Built $APP ($MODE)"

if [[ "$MODE" == "release" ]]; then
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  mkdir -p dist
  ditto -c -k --keepParent $APP "$T/notarize.zip"
  xcrun notarytool submit "$T/notarize.zip" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" --wait
  xcrun stapler staple $APP
  rm -f dist/Router.zip
  ditto -c -k --keepParent $APP dist/Router.zip
  spctl -a -vv $APP
  echo "Release ready: dist/Router.zip. Next: tools/make-appcast.sh"
fi

if [[ "$MODE" == "install" ]]; then
  pkill -x Router || true
  rm -rf /Applications/Router.app && cp -R $APP /Applications/ && open /Applications/Router.app
fi
