#!/bin/zsh
# Creates the signed Sparkle feed (dist/appcast.xml) for the notarized zip in dist/.
# Run `./build.sh release` first. The EdDSA private key is read from the login Keychain by generate_appcast.
#
#   tools/make-appcast.sh
#
# Afterwards publish both files to a GitHub release (the app reads releases/latest/download/appcast.xml):
#   gh release create v<version> dist/Router.zip dist/appcast.xml --title "Router <version>" --notes-file notes/<version>.md
# Installed copies pick it up on their next check.
set -e
cd "$(dirname "$0")/.."
ZIP=dist/Router.zip
[[ -f $ZIP ]] || { echo "dist/Router.zip not found: run ./build.sh release first" >&2; exit 1; }
VERSION=$(unzip -p $ZIP Router.app/Contents/Info.plist | plutil -extract CFBundleShortVersionString raw -o - -)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp $ZIP "$T/Router.zip"
# release notes shown in Sparkle's update window (notes/<version>.md, optional)
[[ -f notes/$VERSION.md ]] && cp notes/$VERSION.md "$T/Router.md"

.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/os7borne/router/releases/download/v$VERSION/" \
  --embed-release-notes \
  -o dist/appcast.xml "$T"
echo "Wrote dist/appcast.xml for v$VERSION"
