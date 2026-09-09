# Claude Usage Menu Bar

A macOS menu bar app that shows your Claude Code token usage and estimated
cost, updated every 3 seconds. No API key, no network access — it reads your
own local session logs at `~/.claude/projects/**/*.jsonl`.

Shows in the menu bar: total tokens + estimated cost for today. Click it for
a breakdown by model, the currently active session's usage, and a refresh
button.

## Why a menu bar app, not a Notification Center widget

Real macOS WidgetKit widgets refresh on an OS-controlled budget (minutes to
hours) — they can't push live updates, and building one requires the full
Xcode.app (not just Command Line Tools) to build a widget extension target
and its App Group entitlement. A `MenuBarExtra` app updates continuously
while running and needs only the Swift toolchain, which is why this project
uses that instead.

## Build & run

```bash
swift build -c release
.build/release/ClaudeUsageMenuBar
```

Or build a proper double-clickable `.app`:

```bash
./build_app.sh
open ClaudeUsageMenuBar.app
```

## Run automatically at login

1. `./build_app.sh`
2. Move `ClaudeUsageMenuBar.app` to `/Applications`
3. System Settings → General → Login Items → add it under "Open at Login"

## How the numbers are computed

- Tails every `*.jsonl` under `~/.claude/projects` incrementally (byte-offset
  tracked per file), so it stays cheap even as logs grow.
- Counts each assistant turn's `usage` block once, deduped by `requestId`.
- "Today" resets at local midnight.
- Cost uses Anthropic's first-party per-token pricing for the models in
  `Sources/ClaudeUsageMenuBar/UsageModels.swift`. A model not in that table
  contributes tokens but no cost, and the popover flags this so the total
  isn't silently understated.

## Notes

- The app was smoke-tested (builds, launches, stays resident, exits cleanly)
  in a headless session with no attached display, so the menu bar UI itself
  hasn't been visually confirmed — check that the popover renders as
  expected the first time you run it.
- Ad-hoc signed (`codesign -s -`) — fine for local use; Gatekeeper may still
  warn on first launch since it isn't notarized. Right-click → Open once to
  bypass.
