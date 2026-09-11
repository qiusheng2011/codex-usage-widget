# AGENTS.md

## Project scope

This repository contains a lightweight macOS AppKit floating widget and a native
WidgetKit desktop widget for Codex usage. Both are built without an Xcode project or
external package dependencies.

## Repository layout

- `Sources/CodexUsageWidget.swift`: application, AppKit UI, local Codex app-server client,
  usage history, charts, menu-bar status item, appearance settings, and compact edge mode.
- `Sources/CodexUsageDesktopWidget.swift`: WidgetKit extension that reads the latest local
  usage history and renders small and medium desktop widgets.
- `AppBundle/Contents/Info.plist`: source bundle metadata. Edit this file when bundle
  metadata must change.
- `AppBundle/Widget/Info.plist`: source metadata for the WidgetKit extension.
- `AppBundle/Widget/Entitlements.plist`: sandbox and read-only local-history permissions
  for the WidgetKit extension.
- `build.zsh`: canonical build script. It compiles the AppKit app and WidgetKit extension,
  copies their plists, creates the app bundle, and applies ad-hoc signatures.
- `assets/preview.png`: README preview image.
- `README.md`: user-facing behavior and launch instructions.

The generated `AppBundle/Codex Usage Widget.app/` is build output and is ignored by Git.
Do not edit files inside the generated app bundle directly; rebuild it instead.

## Build and validation

Run the canonical build from the repository root:

```zsh
./build.zsh
```

Useful validation commands:

```zsh
git diff --check
plutil -lint 'AppBundle/Contents/Info.plist'
plutil -lint 'AppBundle/Widget/Info.plist'
```

To launch the built UI:

```zsh
open "AppBundle/Codex Usage Widget.app"
```

For a headless, sanitized connectivity check:

```zsh
"AppBundle/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget" --once
```

The `--once` mode prints one sanitized usage snapshot and exits. Do not claim UI behavior
was visually verified unless the built app was actually launched and inspected.

## Implementation constraints

- Keep the app read-only with respect to the local Codex app-server. It must not read,
  copy, persist, or expose authentication tokens.
- Preserve the refresh policy: successful updates are scheduled every 30 seconds;
  failed or timed-out updates retry after 1 second.
- Preserve usage history at
  `~/Library/Application Support/Codex Usage Widget/usage-history.jsonl`. This data is
  outside the app bundle so rebuilding or updating the app does not remove it. Maintain
  backward-compatible decoding when changing the history model.
- Keep the distinction between the primary rate-limit window (`rateLimits.primary` and
  its `resetsAt`) and available manual reset credits
  (`rateLimitResetCredits.availableCount` and its available `credits` records).
- Keep appearance and compact-mode preferences in `UserDefaults`; new preferences must
  have explicit defaults and must not break existing saved settings.
- Keep the menu-bar usage format stable as `CODEX(5h:<primary>% |1W <secondary>%)`.
  The menu-bar display preference is enabled by default unless the user has explicitly
  disabled it.
- Keep the desktop widget read-only: it may read the latest successful snapshot from
  `~/Library/Application Support/Codex Usage Widget/usage-history.jsonl`, but must not
  access the local Codex app-server or authentication data.
- Keep the WidgetKit extension sandboxed and restrict its temporary file exception to the
  local usage-history directory.
- The current minimum macOS version is 13.0. Prefer APIs available on macOS 13 and avoid
  introducing dependencies unless the task explicitly requires them.
- Use programmatic AppKit layout consistent with the existing code. Keep controls
  accessible with meaningful tooltips and accessibility labels.

## Change workflow

1. Inspect `git status` and the relevant source before editing. Preserve unrelated user
   changes, including staged, unstaged, and untracked files.
2. Make focused changes in the source files. Use `apply_patch` for text edits.
3. Update `README.md` when user-visible behavior or controls change.
4. Run `./build.zsh`, then run the focused validation commands above. For UI changes,
   perform a real launch/inspection when the environment permits it.
5. Review the final diff and status. Never stage generated app bundles or unrelated
   pre-existing changes.

## Git commit policy

- After the relevant build and validation checks pass, automatically create a clear,
  task-only Git commit for the changes made in the current task.
- Stage only files belonging to the current task. Do not include pre-existing user
  modifications, generated app output, local history, or unrelated files.
- Never run `git push` or otherwise publish changes to a remote. The user will push
  commits separately.
- Do not use destructive commands such as `git reset --hard` or `git checkout --` to
  discard user work.
