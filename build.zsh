#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
APP="$ROOT/AppBundle/Codex Usage Widget.app"
DMG="$ROOT/AppBundle/Codex Usage Widget.dmg"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/AppBundle/Contents/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc "$ROOT/Sources/CodexUsageWidget.swift" -framework AppKit -o "$APP/Contents/MacOS/CodexUsageWidget"
codesign --force --sign - "$APP" >/dev/null

DMG_STAGING=$(mktemp -d "$ROOT/AppBundle/.dmg-staging.XXXXXX")
cleanup() {
  rm -rf "$DMG_STAGING"
}
trap cleanup EXIT
cp -R "$APP" "$DMG_STAGING/"
hdiutil create \
  -volname "Codex Usage Widget" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "Built: $APP"
echo "Packaged: $DMG"
