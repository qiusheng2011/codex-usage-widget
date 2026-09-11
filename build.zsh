#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
APP="$ROOT/AppBundle/Codex Usage Widget.app"
DMG="$ROOT/AppBundle/Codex Usage Widget.dmg"
ICON_SOURCE="$ROOT/assets/icon.png"
ICON_RESOURCE="$APP/Contents/Resources/AppIcon.icns"
WIDGET="$APP/Contents/PlugIns/Codex Usage Widget Desktop.appex"
WIDGET_BINARY="$WIDGET/Contents/MacOS/CodexUsageDesktopWidget"
WIDGET_PLIST="$ROOT/AppBundle/Widget/Info.plist"
WIDGET_ENTITLEMENTS="$ROOT/AppBundle/Widget/Entitlements.plist"

if [[ ! -f "$ICON_SOURCE" ]]; then
  print -u2 "Missing app icon source: $ICON_SOURCE"
  exit 1
fi

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$WIDGET/Contents/MacOS"
cp "$ROOT/AppBundle/Contents/Info.plist" "$APP/Contents/Info.plist"
cp "$WIDGET_PLIST" "$WIDGET/Contents/Info.plist"
xcrun swiftc "$ROOT/Sources/CodexUsageWidget.swift" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  -framework UserNotifications \
  -framework WidgetKit \
  -o "$APP/Contents/MacOS/CodexUsageWidget"
xcrun swiftc "$ROOT/Sources/CodexUsageDesktopWidget.swift" \
  -target arm64-apple-macosx13.0 \
  -parse-as-library \
  -module-name CodexUsageWidgetDesktop \
  -framework SwiftUI \
  -framework WidgetKit \
  -o "$WIDGET_BINARY"

ICONSET_STAGING=""
DMG_STAGING=""
cleanup() {
  if [[ -n "$ICONSET_STAGING" ]]; then
    rm -rf "$ICONSET_STAGING"
  fi
  if [[ -n "$DMG_STAGING" ]]; then
    rm -rf "$DMG_STAGING"
  fi
}
trap cleanup EXIT

ICONSET_STAGING=$(mktemp -d "$ROOT/AppBundle/.iconset.XXXXXX")
ICONSET="$ICONSET_STAGING/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  doubleSize=$((size * 2))
  sips -z "$doubleSize" "$doubleSize" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
if ! iconutil -c icns "$ICONSET" -o "$ICON_RESOURCE"; then
  if [[ -f "$ICON_RESOURCE" ]]; then
    print -u2 "Warning: iconutil could not rebuild the icon; preserving the existing AppIcon.icns."
  else
    print -u2 "Unable to create AppIcon.icns: iconutil failed and no existing icon is available."
    exit 1
  fi
fi

codesign --force --sign - --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET" >/dev/null
codesign --force --sign - "$APP" >/dev/null

DMG_STAGING=$(mktemp -d "$ROOT/AppBundle/.dmg-staging.XXXXXX")
cp -R "$APP" "$DMG_STAGING/"
hdiutil create \
  -volname "Codex Usage Widget" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "Built: $APP"
echo "Packaged: $DMG"
