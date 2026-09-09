# Claude Usage Menu Bar

A macOS menu bar app that shows a live graphical gauge of your Claude Pro/Max
**plan usage limits** — the same "Current session" / "Current week" percentages
Claude Code's own `/usage` command reports — right in the menu bar icon.

Menu bar icon: a colored ring (green/yellow/red) + percentage for the current
session's usage. Click it for both the session and weekly gauges with reset
countdowns, plus a supplementary breakdown of today's local token usage/cost.

## Where the numbers come from

The plan-usage gauge shells out to the real `claude` CLI (`claude -p '/usage'
--output-format json`) every 60 seconds — the same code path Claude Code
itself uses to render "Plan usage limits" — rather than reverse-engineering
an undocumented API endpoint. If `claude` isn't on `PATH` or the parse fails,
the popover shows the raw error instead of guessing.

The supplementary "today" section reads your own local session logs at
`~/.claude/projects/**/*.jsonl` — no API key, no network access for that part.

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

- **Plan usage (primary gauge):** parses the `result` text of `claude -p
  '/usage' --output-format json`, extracting "Current session: N% used ·
  resets <date> (<IANA timezone>)" and the equivalent weekly line via regex.
  Reset countdowns are computed from the parsed date/timezone.
- **Local logs (supplementary):** tails every `*.jsonl` under
  `~/.claude/projects` incrementally (byte-offset tracked per file), counts
  each assistant turn's `usage` block once (deduped by `requestId`), and
  prices it against `Sources/ClaudeUsageMenuBar/UsageModels.swift`. "Today"
  resets at local midnight. A model missing from that pricing table
  contributes tokens but no cost, and the popover flags this.

## Notes

- The app was smoke-tested end-to-end (builds, launches, survives a full
  60s plan-usage fetch cycle, exits cleanly) in a headless session with no
  attached display, so the menu bar UI itself hasn't been visually
  confirmed — check that the ring gauge and popover render as expected the
  first time you run it.
- The `claude -p '/usage'` call was verified to return an abbreviated
  response (no percentages) when its process tree has another `claude`
  process as an ancestor — e.g. running the built binary directly inside an
  active Claude Code session's terminal. A normal launch (Finder,
  `open`, Login Items) has no such ancestor and returns full data; this was
  confirmed via a process path with no `claude` ancestor. If you ever do see
  "Couldn't read plan usage" in the popover, check whether you launched it
  from inside a Claude Code session.
- Ad-hoc signed (`codesign -s -`) — fine for local use; Gatekeeper may still
  warn on first launch since it isn't notarized. Right-click → Open once to
  bypass.
