#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc "$ROOT/Sources/Models.swift" "$ROOT/Sources/UsageClient.swift" \
  "$ROOT/Tests/SystemProxyEnvironmentTests.swift" \
  -target arm64-apple-macosx13.0 -parse-as-library \
  -framework AppKit -framework UserNotifications -framework WidgetKit \
  -o "$TEST_DIR/proxy-tests"
"$TEST_DIR/proxy-tests"
