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
runs `claude` as a directly-exec'd subprocess (resolved to its binary path,
no shell involved at all), which macOS never gates behind a permission
prompt.

Two earlier approaches both leaked into things this app has no business
touching, and both were reverted after real-world testing caught them:

1. Routing `claude -p '/usage'` through AppleScript's `do shell script`
   (to reliably get full data) triggered unrelated Automation permission
   prompts — Photos, Music, Desktop folder access — confirmed by removing
   the app and watching the prompts stop.
2. Routing it through `/bin/zsh -l -c "claude ..."` (to load `PATH` the way
   a terminal does) triggered an unrelated "access files on a network
   volume" prompt — almost certainly something in the user's shell startup
   files (`.zprofile`/`.zshrc`, oh-my-zsh, nvm, etc.), which is a black box
   this app has no reason to execute at all just to run one command.

The current approach resolves `claude`'s binary path with plain filesystem
checks (`~/.local/bin`, Homebrew paths, nvm's versioned node dirs) and execs
it directly with an explicit, minimal environment (`HOME`, `USER`, a basic
`PATH`) — no shell, no profile sourcing, no AppleScript. This turned out to
also fix the data-completeness issue below as a side effect.

## Where the numbers come from

The plan-usage gauge runs the real `claude` CLI (`claude -p '/usage'
--output-format json`) every 60 seconds — the same code path Claude Code
itself uses to render "Plan usage limits" — rather than reverse-engineering
an undocumented API endpoint or scraping Keychain-stored credentials.

An earlier version of the direct-exec approach (routed through a login shell)
sometimes got an abbreviated response with no percentages. Bypassing the
shell entirely — exec'ing the resolved binary path directly with a minimal
environment — reliably returns full data in testing (verified via a
`launchd`-submitted job, fully detached from any parent process, matching
how a real double-clicked app spawns). If `claude -p '/usage'` ever does
return without percentages, the popover shows "Live percentages unavailable
right now" and keeps retrying every 60s, rather than showing a stale or
guessed number — the local-log token/cost section below it stays accurate
regardless.

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
