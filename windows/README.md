> 🌏 **English** · [简体中文](README.zh-CN.md)

# Fusion Workbench — Windows port (WPF, C#, .NET 8)

All-English port of the macOS "Fusion Workbench" SwiftUI dashboard
(see the repo root `README.md` and `Sources/FusionWorkbench/` for the original).
This tree lives entirely under `windows/` and is meant to be published as a new,
independent, all-English source tree in a public GitHub repository.

The macOS dashboard shows seven resizable glass cards. This Windows port keeps the same seven
modules and the same *no fake data* rule: when a source cannot answer (CLI missing, network
down, invalid settings, macOS-only source), the card shows an explicit **Unavailable** state
with the reason — never synthesized numbers.

| # | Module | Windows card |
|---|--------|--------------|
| 1 | weather | `Views/WeatherCard` — Nullschool earth map |
| 2 | system | `Views/SystemCard` — live CPU / RAM / disk of this PC |
| 3 | codex | `Views/CodexCard` — Unavailable (macOS-only source) |
| 4 | commandCode | `Views/CommandCodeCard` — Unavailable (macOS-only source) |
| 5 | github | `Views/GitHubCard` — GitHub CLI account overview |
| 6 | makerWorld | `Views/MakerWorldCard` — MakerWorld account overview |
| 7 | harness | `Views/HarnessCard` — Unavailable (macOS-only source) |

---

## Prerequisites

- **Windows 10 version 1809+ or Windows 11**
- **[.NET SDK 8.0](https://dotnet.microsoft.com/download/dotnet/8.0)** (the `net8.0-windows` target includes WPF)
- Optional but recommended: **Visual Studio 2022** with the ".NET desktop development" workload
- **WebView2 Runtime** for the weather card only. Windows 11 and updated Windows 10 machines
  already ship it via Microsoft Edge. If the weather card reports
  *"WebView2 Runtime is required…"*, install the
  [Evergreen WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) and restart.
  The rest of the dashboard works without it.
- **GitHub CLI (`gh`)** only for the GitHub card, see below.

## Build & run

```powershell
# From this windows/ folder
dotnet build FusionWorkbench.sln -c Release
dotnet run --project FusionWorkbench/FusionWorkbench.csproj
```

Or open `FusionWorkbench.sln` in Visual Studio 2022 and press **F5**.
The only NuGet dependency is `Microsoft.Web.WebView2` (1.0.2739.15), declared in
`FusionWorkbench/FusionWorkbench.csproj`.

## GitHub CLI

The GitHub card mirrors the macOS original and shells out to the official GitHub CLI:

```powershell
winget install GitHub.cli
gh auth login          # then follow the interactive sign-in
```

Restart Fusion Workbench (or click **Refresh now**). When `gh` is missing or not signed in,
the card shows Unavailable with an install / sign-in hint. `gh` is resolved through `PATH`;
no token is stored by this app. (A token-based REST path is intentionally out of scope:
"gh only", as documented in `Services/GitHubService.cs`.)

## MakerWorld user ID

The MakerWorld card needs the numeric ID of a public profile
(`makerworld.com/u/12345678` → `12345678`):

1. Click **Settings** in the top toolbar.
2. Paste the numeric ID into the *MakerWorld user ID* field and click **Save**.

The value is stored locally as plain JSON in
`%LOCALAPPDATA%\FusionWorkbench\settings.json`.
While the field is empty (or not numeric), the card shows Unavailable with
*"Set your MakerWorld user ID (Settings) to enable this card."*

## Data-source availability (Windows vs macOS)

| Card | Windows | macOS | Notes |
|------|---------|-------|-------|
| System | **Live** — CPU & RAM via `kernel32` (`GetSystemTimes` deltas, `GlobalMemoryStatusEx`); disk via `DriveInfo` | Live (host_statistics / IOKit) | First CPU reading appears after the second 30 s sample (baseline). |
| GitHub | **Live** — shells out to `gh api user`, `gh api user/repos`, `gh api user/orgs` | Live — same three `gh` calls | Unavailable when `gh` missing / not signed in / offline. Repo counts reflect the first 100 owner repositories (same cap as macOS). |
| MakerWorld | **Live** — Bambu Lab API `design-user-service/user/profile/{id}` + per-design details (≤ 4) | Live | Requires numeric user ID in Settings. Timeout 15 s, browser-like User-Agent. |
| Weather | **Live map** — WebView2 → `https://earth.nullschool.net/` | Live — WKWebView → same URL | Needs the WebView2 Runtime + internet. WebView2 missing / navigation failure → Unavailable overlay. |
| Harness | Unavailable | Live | macOS reads the local DeepSeek Harness store `~/.dsh`. No such store exists on Windows. |
| Codex | Unavailable | Live | macOS talks to the Codex `app-server` binary inside the ChatGPT app. |
| Command Code | Unavailable | Live | macOS runs the Command Code CLI inside the Command Code app. |

## Language toggle (English / Chinese)

The top toolbar switches the interface language **at runtime** without restarting.
All user-facing text is looked up through `DynamicResource` from
`Localization/Strings.en.xaml` / `Localization/Strings.zh.xaml`; `App.ApplyLanguageCore`
re-orders the merged dictionaries and the view models re-localize their computed strings.
The two dictionaries always contain the same key set. The choice is persisted in
`%LOCALAPPDATA%\FusionWorkbench\settings.json`. The button labels ("English" and the two
Chinese characters for "Chinese") are stored as dictionary values, identical in both
dictionaries — the only non-English UI text in the app lives inside `Strings.zh.xaml` values.

## Layout & refresh

- The dashboard is a proportional grid (`Grid` with `*` rows/columns); every card is a rounded,
  semi-transparent `Border` (glass look) with a header (status dot + title + status word), a
  body and an "Updated HH:mm:ss" footer. All cards resize with the window; text never scales or
  distorts.
- CPU / RAM / disk bars use the same coloring rule as the macOS original
  (`LiveLayout.usageColor`): hue walks 120° (green, low usage) → 0° (red, high usage) via
  `Converters/UsageToBrushConverter`; a `null` value renders neutral gray.
- A `DispatcherTimer` ticks every second and triggers a full refresh every **30 s**; the toolbar
  shows the countdown ("next in N s"). Each source runs on background work with its own timeout
  (12–15 s) so a dead network never freezes the UI. **Refresh now** restarts the cycle.

## Design decisions worth knowing

- **Weather = Nullschool WebView2 only.** The macOS card is a WKWebView of
  `https://earth.nullschool.net/`, so the port mirrors it with `Microsoft.Web.WebView2`.
  An Open-Meteo text line was deliberately *not* added: one primary approach keeps the code, the
  failure modes and this README small. See `Services/WeatherService.cs`.
- **System metrics** use P/Invoke on `kernel32` (`GetSystemTimes`, `GlobalMemoryStatusEx`).
  CPU is the whole-machine utilization from idle/kernel/user deltas between samples
  (same idea as the macOS `host_statistics` delta). `System.Diagnostics.PerformanceCounter` is
  avoided because it depends on the (sometimes broken/absent) Windows performance counters and
  requires extra privileges on some machines.
- **No internet / no CLI / no data is never faked.** Each service returns a snapshot marked
  Available only when it really answered; every other path carries a localization key such as
  `Msg_GhNotFound`, `Msg_Timeout` or `Msg_MacOSOnly_Harness` that the card displays verbatim.
- **GitHub repository counts** come from `gh api user/repos?per_page=100&affiliation=owner`
  (same query as macOS), so they cover up to 100 owner repositories.
- **MakerWorld design details** are capped at 4 fetches per refresh so the 30 s cycle stays
  responsive; aggregated counters (`designCount`, downloads, prints) come from the profile's
  `MWCount` block exactly like macOS.

## Troubleshooting

- **Build errors about XAML / missing namespaces**: run `dotnet restore` first; make sure the
  .NET 8 SDK's Windows desktop workload is installed (`dotnet workload list`).
- **Weather card shows "WebView2 Runtime is required…"**: install the Evergreen WebView2 Runtime
  and restart the app (see Prerequisites).
- **Weather card shows "Could not load the earth map…"**: you are offline or earth.nullschool.net
  is unreachable; click **Retry** once the network is back. All other cards then show their own
  Unavailable reasons.
- **GitHub card shows a gh error**: run `gh auth login`; verify `gh` is on `PATH`
  (`gh --version` in a new terminal) and that the machine has internet access.
- **MakerWorld card stays unavailable after Settings**: make sure the ID is a plain number from
  the profile URL and that the machine can reach `api.bambulab.com`.
- **Nothing is fake by design**: when in doubt, the card tells you exactly why it cannot show
  data instead of guessing.
