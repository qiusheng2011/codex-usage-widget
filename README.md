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
- The appearance settings support switching between Chinese and English; Chinese is the default and the choice is remembered locally
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

For Xcode development, open `CodexUsageWidget.xcodeproj`. Its `Codex Usage Widget`
scheme builds the AppKit host and embeds the `Codex Usage Widget Desktop` extension.
The project uses ad-hoc signing by default and shares the same source plists and
entitlements as `build.zsh`.

After installing or launching the app, add “Codex 用量” from the macOS desktop widget
gallery. The gallery uses the host app's display name, so search for the exact name
“Codex 用量”. The widget is packaged inside the app as a WidgetKit extension.

Desktop widgets use a dark background in full color and the system background with
adaptive foreground colors in unfocused/monochrome mode, with one content inset. Gallery
previews show sample values; placed widgets read the host app's local usage history.

For a headless, sanitized connectivity check:

```zsh
"AppBundle/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget" --once
```

`--once` runs without starting the AppKit host or WidgetKit, so it doesn't register the
temporary build as a duplicate desktop-widget provider.

## Privacy-preserving package signing on macOS 26

The build links the widget through `_NSExtensionMain`, matching Xcode's extension
startup. Without this entry point, the extension can register successfully but exit
before responding to gallery requests on macOS 26. Signing and registration checks
alone do not verify gallery availability.

The default build uses an ad-hoc signature so the published app and DMG don't embed an
Apple developer name, email address, or Team ID:

```zsh
./build.zsh
```

The build checks both the host app and WidgetKit extension after signing and stops if an
Apple signing authority or Team ID is unexpectedly present. This protects the package,
but doesn't remove author emails already stored in Git history.

Ad-hoc packages aren't notarized, so users may need to explicitly approve the app on
first launch. Desktop Widget availability must be tested on the target macOS release;
the extension still uses the native `_NSExtensionMain` entry point required by macOS 26.
