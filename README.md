# Codex Usage Widget

A lightweight macOS floating widget that sits beside Codex and shows Codex usage continuously.

中文说明：[README.zh-CN.md](README.zh-CN.md)

![Codex Usage Widget preview](assets/preview.png)

- Primary Codex rate-limit percentage and reset time
- Sends a macOS local notification when the five-hour rate-limit window resets; notification permission is requested on first launch
- Secondary rate-limit percentage when the account provides one
- Latest available daily token bucket and cumulative token count
- Refreshes every 30 seconds, retrying every 1 second after a failed update; the panel shows the update time, force-refresh, hide, and exit buttons
- The hide button dismisses the floating widget while keeping the local refresh process running; click the menu-bar usage widget to show it again
- Includes a native macOS desktop widget in small and medium sizes with the same core usage display; click it to open the floating widget
- The history chart button opens a filtered trend chart with 24-hour, 7-day, 30-day, or all-history ranges and primary/secondary/both metric selections
- Shows available manual reset credits beside the reset time; click the count to view each available credit's expiration when the app-server provides details
- The appearance settings support a custom background image and image opacity; the existing dark theme color remains overlaid, and automatic compact scaling can be enabled with a configurable 1–10 second delay
- The menu bar can show live usage as `CODEX(5h:42%|1W:18%)`; its visibility is configurable and enabled by default
- Drag the panel near a screen edge to snap and collapse it to a minimal 5-hour/long-cycle view; hover over it to restore the full panel
- `assets/icon.png` is used as the application icon and is converted to a multi-resolution `AppIcon.icns` during the build
- Appends every successful usage record to `~/Library/Application Support/Codex Usage Widget/usage-history.jsonl`; the history is kept outside the app bundle so app updates do not remove it

## Privacy and network

This project runs locally on macOS. The widget and its WidgetKit desktop extension make no
outbound network requests and contain no telemetry, analytics, advertising, tracking, or
cloud synchronization. The floating app communicates with the local `codex app-server`
process in read-only mode. The desktop extension only reads the latest usage snapshot from
the local history file. Neither component reads, copies, or saves authentication tokens,
prompts, files, or other user content.

The separate Codex app-server may have its own network behavior; that independent behavior
is outside this widget and is not controlled by this project.

## Launch

Open `AppBundle/Codex Usage Widget.app`, or run:

```zsh
open "AppBundle/Codex Usage Widget.app"
```

To rebuild after a Codex update:

```zsh
./build.zsh
```

The build creates both `AppBundle/Codex Usage Widget.app` and the installation image
`AppBundle/Codex Usage Widget.dmg`.

After installing or launching the app, add “Codex 用量” from the macOS desktop widget
gallery. The gallery uses the host app's display name, so search for the exact name
“Codex 用量”. The widget is packaged inside the app as a WidgetKit extension.

For a headless, sanitized connectivity check:

```zsh
"AppBundle/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget" --once
```

`--once` runs without starting the AppKit host or WidgetKit, so it doesn't register the
temporary build as a duplicate desktop-widget provider.

## Widget signing on macOS 26

Use an Apple signing identity when packaging an app that needs to appear in the desktop
widget gallery. An ad-hoc signature can run locally but macOS may filter its WidgetKit
extension from the gallery. After signing in to Xcode with an Apple Developer account,
pass the available identity to the build:

```zsh
CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.zsh
```

For direct distribution, use a `Developer ID Application` identity and notarize the app.
