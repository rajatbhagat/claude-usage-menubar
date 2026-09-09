# Claude Usage Menu Bar

A macOS menu bar app that shows a live graphical gauge of your Claude Pro/Max
**plan usage limits** — the same "Current session" / "Current week" percentages
Claude Code's own `/usage` command reports — right in the menu bar icon.

Menu bar icon: a colored ring (green/yellow/red) + percentage for the current
session's usage. Click it for both the session and weekly gauges with reset
countdowns, plus a supplementary breakdown of today's local token usage/cost.

## Permission footprint (by design)

This app requests **zero macOS permissions**: no entitlements, no
`Info.plist` usage-description keys, no Photos/Music/Automation/Files access
of any kind — verified with `codesign -d --entitlements` and by inspecting
`Info.plist` directly. It reads only your own `~/.claude/projects` logs and
runs `claude` as a plain subprocess, which macOS never gates behind a
permission prompt.

An earlier version routed the `claude -p '/usage'` call through AppleScript's
`do shell script` to work around a data-availability issue (below). That
reliably got full data, but real-world testing showed it also triggered
unrelated macOS Automation permission prompts (Photos, Music, Desktop folder
access) — confirmed by removing the app and watching the prompts stop. That
approach was reverted. The tradeoff: the live percentages aren't always
available (see next section), but the app never asks for anything it
shouldn't.

## Where the numbers come from, and a known limitation

The plan-usage gauge shells out to the real `claude` CLI (`claude -p '/usage'
--output-format json`) every 60 seconds — the same code path Claude Code
itself uses to render "Plan usage limits" — rather than reverse-engineering
an undocumented API endpoint or scraping Keychain-stored credentials.

**Known limitation:** `claude -p '/usage'` sometimes omits the percentages
when run as a plain headless subprocess (no controlling terminal) — this was
confirmed even when the subprocess has no `claude` ancestor at all (tested
via a `launchd`-submitted job, matching how a real double-clicked app
spawns), so it isn't a nested-session artifact. Root cause isn't confirmed.
When this happens, the popover shows "Live percentages unavailable right
now" instead of a stale or guessed number, and keeps retrying every 60s —
the local-log token/cost section below it stays accurate regardless.

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
  confirmed beyond what the user directly reported.
- Ad-hoc signed (`codesign -s -`) — fine for local use; Gatekeeper may still
  warn on first launch since it isn't notarized. Right-click → Open once to
  bypass. Note ad-hoc signatures change on every rebuild, so macOS may treat
  a rebuilt app as a "new" app for any permission it does end up needing in
  the future — not an issue today since it requests none.
