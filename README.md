# Codex Usage Widget

A lightweight macOS floating widget that sits beside Codex and shows Codex usage continuously.

- Primary Codex rate-limit percentage and reset time
- Secondary rate-limit percentage when the account provides one
- Latest available daily token bucket and cumulative token count
- Refreshes every 30 seconds, retrying every 1 second after a failed update; the panel shows the update time, a force-refresh button, and an exit button
- The history chart button opens a filtered trend chart with 24-hour, 7-day, 30-day, or all-history ranges and primary/secondary/both metric selections
- Shows available manual reset credits beside the reset time; click the count to view each available credit's expiration when the app-server provides details
- Appends every successful usage record to `~/Library/Application Support/Codex Usage Widget/usage-history.jsonl`; the history is kept outside the app bundle so app updates do not remove it

It calls the local `codex app-server` in read-only mode. It does not read, copy, or save authentication tokens.

## Launch

Open `AppBundle/Codex Usage Widget.app`, or run:

```zsh
open "AppBundle/Codex Usage Widget.app"
```

To rebuild after a Codex update:

```zsh
./build.zsh
```

For a headless, sanitized connectivity check:

```zsh
"AppBundle/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget" --once
```
