#!/bin/zsh
# Builds Router.app (ad-hoc signed). Usage: ./build.sh [install]
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Router.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/Router $APP/Contents/MacOS/Router
cp Info.plist $APP/Contents/Info.plist
mkdir -p $APP/Contents/Resources build/AppIcon.iconset
swift tools/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns
# Sign with a stable identity so macOS keeps the Location permission across rebuilds
# (ad-hoc signing changes the app's identity on every build and resets permissions).
ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}
if [[ -z "$ID" ]]; then ID=$(security find-identity -v -p codesigning | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"'); fi
if [[ -n "$ID" ]]; then echo "Signing as: $ID"; codesign --force --sign "$ID" $APP
else echo "No signing identity found, using ad-hoc (Location permission will reset each build)"; codesign --force --sign - $APP; fi
echo "Built $APP"
if [[ "$1" == install ]]; then
  pkill -x Router || true
  rm -rf /Applications/Router.app && cp -R $APP /Applications/ && open /Applications/Router.app
fi
