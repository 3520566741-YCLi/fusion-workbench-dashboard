# Customizing Fusion Workbench with your own AI

Fusion Workbench is a **framework**, not a finished product. The intended way to
use it is: download → give it to your own AI coding assistant → let it adapt
everything to *your* machines, accounts and data.

This file tells you how to do that safely and quickly — for the macOS app and
for the Windows app.

---

## 1. Download

- **Whole repository (both versions):** GitHub → **Code ▾ → Download ZIP**, or
  `git clone https://github.com/3520566741-YCLi/fusion-workbench-dashboard.git`
- The macOS app is the Swift package at the repo root
  (`Sources/FusionWorkbench/`). The Windows app is `windows/`.
- Build instructions: repo root `README.md` (macOS) and `windows/README.md`
  (Windows).

## 2. Tell your AI assistant what to do

The project contains **no personal data** — all data sources are either empty
and waiting for your values, or macOS/Windows local state. Hand it to an AI
coding agent (Claude Code, Codex, DeepSeek Harness, Gemini CLI, …) with a brief
like this:

> "I downloaded the Fusion Workbench dashboard. Please adapt it for me:
> 1. Read the README and the module samplers/services first.
> 2. Replace the empty/placeholder data sources with mine:
>    - GitHub → use my `gh` login (or a token if I give you one)
>    - MakerWorld → set my numeric user id
>    - System/metrics → keep, verify it reads my machine correctly
>    - Anything macOS-only (Harness / Codex / Command Code) that I don't use →
>      hide that card or point it at a real source I do have
> 3. Keep the no-fake-data rule: unavailable = say Unavailable, never invent
>    numbers.
> 4. UI language: keep the English default and the Chinese toggle.
> 5. Build it and fix any compile errors; show me a screenshot."

Tell it **which OS you are on** and paste any **error output** it needs.

## 3. Privacy rules to give your AI

- Never hard-code personal ids, tokens or paths into the code. Put secrets in
  the app's Settings / `UserDefaults` / environment — never in files you might
  re-publish.
- The macOS MakerWorld id is read from the `makerWorldUserID` user default
  (see root README); the Windows version stores it in Settings.
- If you publish your own fork, run a scan for your name, email, ids and
  `~/.` paths before pushing (see the "Privacy & origin" note in the README).

## 4. Typical customization prompts

macOS:
- "Add a new module card for X that calls Y — follow the live-layout
  conventions in `LiveLayout.swift` so its text scales like the others."
- "Change the System card to also show network throughput."
- "Point the GitHub card at my organization repos."
- "Add a 中文 label I missed to `Localization.swift`."

Windows:
- "Adapt the Windows WPF port's GitHub card to use a token I provide instead
  of the `gh` CLI."
- "Fix build error <paste> on my machine (Windows 11, .NET SDK 8)."
- "Add a card for my game server API following the existing card pattern."

## 5. Keep it working

- macOS: always verify with `swift build`, `swift test`, then run the app and
  screenshot it (both languages).
- Windows: always verify with `dotnet build FusionWorkbench.sln -c Release`
  and run it once; screenshot both languages.
- If a data source fails, the card must show **Unavailable + reason** — never
  sample/fake data.
