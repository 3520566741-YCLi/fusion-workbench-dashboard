# Fusion Workbench — Dashboard

A live, resizeable status dashboard for the things you run on your computer:

**macOS app (SwiftUI / Liquid Glass)** — 7 glass cards over a flexible canvas:
- **DeepSeek Harness** — live status of the local Harness (session metadata + local cost ledger)
- **Codex** — active tasks and rate-limit usage of the local Codex agent service
- **Command Code** — local Command Code app status (account, version)
- **GitHub** — your account overview via the GitHub CLI (`gh`)
- **MakerWorld** — your Bambu Lab / MakerWorld profile overview (public API)
- **Mac Status** — CPU / memory / disk / GPU usage
- **Nullschool Earth Weather** — live wind & weather map (WebView)

Every card is genuinely responsive ("live layout"): fonts and spacing scale with
the card, content stretches to fill it vertically, and glyphs are never squashed
or stretched. You can show/hide cards, drag, resize, zoom, auto-arrange and fit
them all onto the canvas.

**Windows app (.NET 8 / WPF)** — a full port of the same 7 cards lives in
[`windows/`](windows/README.md). macOS-only data sources (Harness / Codex /
Command Code) show an explicit **Unavailable** state with a reason instead of
fake data.

---

## ⚠️ Please read first: this is an AI-built template, not a finished product

This repository is **not a turnkey, production dashboard**. It was designed,
written and maintained with **AI coding agents**, and it is intended to be used
the same way:

- Clone it, then hand it to an AI coding assistant and ask it to adapt it for
  your own machines, accounts and data sources.
- Everything is meant to be modified: add modules, change data sources, restyle
  cards, change the language strings, add charts.
- Some features (Liquid Glass, live layout) are deliberately ambitious; treat
  them as a starting point and expect to iterate with an AI.
- No data is ever fabricated: when a source cannot be reached or is not
  configured, cards say **Unavailable** and explain why.

## Features

- **Bilingual UI** — English by default, switchable to 中文 with the toggle in
  the canvas toolbar (macOS) or in the window toolbar (Windows).
- **Honest data** — every card reports real local/network state, or an explicit
  Unavailable reason. Never fake numbers.
- **Liquid Glass (macOS 26)** — real glass cards that sample the content behind
  the transparent window.
- **Flexible live-layout canvas** — drag, resize, zoom, auto-arrange, fit-all;
  card typography scales with the card (factor clamped 0.45×–2×).
- **Privacy by default** — only local non-sensitive metadata is read (session
  titles, timestamps, aggregated cost). Keys, credentials and conversation
  content are never read.

## Repository layout

```
├─ Package.swift              macOS app (Swift Package, SwiftUI)
├─ Sources/FusionWorkbench/   macOS source (7 modules + samplers + localization)
├─ Tests/                     macOS unit tests
├─ windows/                   Windows port (.NET 8 / WPF) + its own README
└─ scripts/build-macos-app.sh package the macOS app into a .app bundle
```

## macOS — build & run

Requirements: **macOS 26+** (Liquid Glass API), **Xcode 26** (Swift 6.2 toolchain).

```bash
swift build -c release          # build the executable
./scripts/build-macos-app.sh    # assemble dist/Fusion Workbench.app (ad-hoc signed)
open "dist/Fusion Workbench.app"
```

Run the unit tests with `swift test`.

## Windows — build & run

See [`windows/README.md`](windows/README.md) — requirements (.NET SDK 8),
build steps, and the per-card data-source availability table.

## Configuration

| Data source | What you need | If missing |
| --- | --- | --- |
| Harness (macOS) | DeepSeek Harness desktop installed, data under `~/.dsh` | Card shows Unavailable |
| Codex (macOS) | Codex CLI in ChatGPT.app on this Mac | Card shows Unavailable |
| Command Code (macOS) | Command Code app installed | Card shows Unavailable |
| GitHub | GitHub CLI installed and logged in (`brew install gh`, `gh auth login`) | Card shows Unavailable + install hint |
| MakerWorld | your MakerWorld profile id | Card shows Unavailable + setup hint |
| System | none | — |
| Nullschool earth map | network access (WebView) | Browser error shown in card |

### Set your MakerWorld profile id

The personal MakerWorld id from the original build was removed for privacy.
Point the card at your own profile:

```bash
defaults write com.fusionworkbench.dashboard makerWorldUserID -int YOUR_ID
```

(Windows: enter the id in the app's Settings field.)

## Localization

Code copy is written in English; the Chinese translation lives in
`Sources/FusionWorkbench/Localization.swift`. Missing keys automatically fall
back to English, so adding a module stays bilingual-safe. When you change
copy, add or update the matching entry in the table.

## Privacy & origin

This public repository is a cleaned-up, English-first re-publication of a
private personal project. Personal identifiers (profile ids, local paths,
usernames, history) were removed and the history was started fresh on purpose.
The Windows port is a source-level port of the macOS modules; it cannot be
built on macOS and was written conservatively to build with a stock .NET 8
SDK. Please report issues on a machine with Windows.

## Feedback

Issues, ideas and module requests are welcome — treat this repo as a living
template.
