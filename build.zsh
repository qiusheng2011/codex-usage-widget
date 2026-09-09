#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
APP="$ROOT/AppBundle/Codex Usage Widget.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/AppBundle/Contents/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc "$ROOT/Sources/CodexUsageWidget.swift" -framework AppKit -o "$APP/Contents/MacOS/CodexUsageWidget"
codesign --force --sign - "$APP" >/dev/null
echo "Built: $APP"
