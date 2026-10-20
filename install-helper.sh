#!/bin/bash
# Build MacDockHelper in Release and install it to /Applications.
# Run from the repo root: ./install-helper.sh
set -euo pipefail
cd "$(dirname "$0")"

[ -d MacDock.xcodeproj ] || xcodegen generate

BUILD_DIR="$(mktemp -d)"
echo "Building MacDockHelper (Release)…"
xcodebuild -project MacDock.xcodeproj -scheme MacDockHelper -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" build -quiet

APP="$BUILD_DIR/Build/Products/Release/MacDockHelper.app"
DEST="/Applications/MacDockHelper.app"

# Quit any running copy so the bundle can be replaced.
osascript -e 'tell application "MacDockHelper" to quit' >/dev/null 2>&1 || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
rm -rf "$BUILD_DIR"

open "$DEST"
echo "Installed and launched $DEST"
echo "Enable 'Launch at login' from the MacDock menu bar icon."
