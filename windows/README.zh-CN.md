> 🌏 [English](README.md) · **简体中文**

# Fusion Workbench —— Windows 移植版（WPF，C#，.NET 8）

这是 macOS “Fusion Workbench” SwiftUI 看板的全英文移植版
（原始版见仓库根目录 [`README.zh-CN.md`](../README.zh-CN.md) 与 `Sources/FusionWorkbench/`）。
本目录全部内容位于 `windows/` 下，作为独立、全英文的源码树随公开仓库发布。

macOS 看板展示七张可缩放的玻璃卡片。本 Windows 移植保留同样的七个模块和
**绝不伪造数据**原则：当数据源无法应答时（缺少 CLI、断网、设置无效、macOS 专属源），
卡片会明确显示 **Unavailable（不可用）** 状态并给出原因——绝不会编造数字。

| # | 模块 | Windows 卡片 |
|---|--------|--------------|
| 1 | weather 天气 | `Views/WeatherCard` —— Nullschool 地球风场图 |
| 2 | system 系统 | `Views/SystemCard` —— 本机 CPU / 内存 / 磁盘实时占用 |
| 3 | codex | `Views/CodexCard` —— 不可用（macOS 专属数据源） |
| 4 | commandCode | `Views/CommandCodeCard` —— 不可用（macOS 专属数据源） |
| 5 | github | `Views/GitHubCard` —— GitHub CLI 账号概览 |
| 6 | makerWorld | `Views/MakerWorldCard` —— MakerWorld 账号概览 |
| 7 | harness | `Views/HarnessCard` —— 不可用（macOS 专属数据源） |

---

## 环境要求

- **Windows 10 版本 1809 及以上，或 Windows 11**
- **[.NET SDK 8.0](https://dotnet.microsoft.com/download/dotnet/8.0)**（`net8.0-windows` 目标已包含 WPF）
- 可选但推荐：**Visual Studio 2022**，并安装 “.NET 桌面开发” 工作负载
- **WebView2 Runtime**（仅天气卡片需要）。Windows 11 与较新的 Windows 10 通常已随
  Microsoft Edge 自带。若天气卡片提示 *“WebView2 Runtime is required…”*，请安装
  [Evergreen WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
  后重启。看板其余部分无需它也能工作。
- **GitHub CLI（`gh`）**（仅 GitHub 卡片需要，见下文）。

## 构建与运行

```powershell
# 在本 windows/ 目录内
dotnet build FusionWorkbench.sln -c Release
dotnet run --project FusionWorkbench/FusionWorkbench.csproj
```

或在 Visual Studio 2022 中打开 `FusionWorkbench.sln` 并按 **F5**。
唯一的 NuGet 依赖是 `Microsoft.Web.WebView2`（1.0.2739.15），声明在
`FusionWorkbench/FusionWorkbench.csproj` 中。

## GitHub CLI

GitHub 卡片与 macOS 原版一致，调用官方 GitHub CLI：

```powershell
winget install GitHub.cli
gh auth login          # 按提示交互式登录
```

重启 Fusion Workbench（或点击 **Refresh now**）。当 `gh` 缺失或未登录时，卡片会显示
Unavailable 并附安装/登录提示。`gh` 通过 `PATH` 解析；本应用不保存任何 token。
（基于 token 的 REST 方案刻意不做：只走 `gh`，见 `Services/GitHubService.cs` 中的说明。）

## MakerWorld 用户 ID

MakerWorld 卡片需要某个公开主页的数字 ID
（`makerworld.com/u/12345678` → `12345678`）：

1. 点击顶部工具栏的 **Settings**。
2. 把数字 ID 粘贴进 *MakerWorld user ID* 字段并点击 **Save**。

该值以纯 JSON 形式保存在
`%LOCALAPPDATA%\FusionWorkbench\settings.json`。
当字段为空（或非数字）时，卡片显示 Unavailable，并提示
*“Set your MakerWorld user ID (Settings) to enable this card.”*

## 数据源可用性（Windows 对比 macOS）

| 卡片 | Windows | macOS | 备注 |
|------|---------|-------|-------|
| System | **可用** —— CPU 与内存经 `kernel32`（`GetSystemTimes` 差值、`GlobalMemoryStatusEx`）；磁盘用 `DriveInfo` | 可用（host_statistics / IOKit） | 首次 CPU 读数出现在第 2 次 30 秒采样之后（需要基线）。 |
| GitHub | **可用** —— 调用 `gh api user`、`gh api user/repos`、`gh api user/orgs` | 可用 —— 同样的三个 `gh` 调用 | `gh` 缺失/未登录/离线时不可用。仓库统计覆盖前 100 个 owner 仓库（与 macOS 相同上限）。 |
| MakerWorld | **可用** —— Bambu Lab API `design-user-service/user/profile/{id}` + 单个设计详情（≤ 4） | 可用 | 需要 Settings 中的数字用户 ID。超时 15 秒，使用类浏览器 User-Agent。 |
| Weather | **可用地图** —— WebView2 → `https://earth.nullschool.net/` | 可用 —— WKWebView → 同一 URL | 需要 WebView2 Runtime 与网络。WebView2 缺失/导航失败 → 显示 Unavailable 浮层。 |
| Harness | 不可用 | 可用 | macOS 读取本地 DeepSeek Harness 数据目录 `~/.dsh`；Windows 上不存在该目录。 |
| Codex | 不可用 | 可用 | macOS 与 ChatGPT 应用内的 Codex `app-server` 可执行程序通信。 |
| Command Code | 不可用 | 可用 | macOS 在 Command Code 应用内运行其 CLI。 |

## 语言切换（英文 / 中文）

顶部工具栏可**运行时**切换界面语言，无需重启。所有用户可见文案都通过
`Localization/Strings.en.xaml` / `Localization/Strings.zh.xaml` 的 `DynamicResource`
查找；`App.ApplyLanguageCore` 会重排合并字典，视图模型也会重新本地化其计算文案。
两份字典始终保持相同的键集合。选择结果保存在
`%LOCALAPPDATA%\FusionWorkbench\settings.json`。按钮标签（“English” 与表示“中文”的两个
汉字）作为字典值存储，两份字典完全一致——应用中唯一的非英文界面文字位于
`Strings.zh.xaml` 的值里。

## 布局与刷新

- 看板为等比网格（使用 `*` 行/列的 `Grid`）；每张卡片都是带圆角的半透明 `Border`
  （玻璃质感），包含标题栏（状态点 + 标题 + 状态词）、内容区与 “Updated HH:mm:ss” 页脚。
  所有卡片随窗口缩放；文字永不缩放或变形。
- CPU / 内存 / 磁盘进度条沿用 macOS 原版的着色规则（`LiveLayout.usageColor`）：
  色相从 120°（绿色，低占用）走到 0°（红色，高占用），由
  `Converters/UsageToBrushConverter` 实现；`null` 值渲染为中性灰。
- 一个 `DispatcherTimer` 每秒触发一次，并每 **30 秒** 执行一次完整刷新；工具栏会显示
  倒计时（“next in N s”）。每个数据源在后台任务中运行并带有自己的超时（12–15 秒），
  因此断网也不会卡死界面。**Refresh now** 会重新开始周期。

## 值得了解的设计决策

- **天气 = 仅用 Nullschool WebView2。** macOS 卡片是对 `https://earth.nullschool.net/`
  的 WKWebView，因此本移植用 `Microsoft.Web.WebView2` 镜像它。刻意**不**加 Open-Meteo
  文字行：单一主方案让代码、失败路径和本文档都保持精简。见 `Services/WeatherService.cs`。
- **系统指标**使用对 `kernel32` 的 P/Invoke（`GetSystemTimes`、`GlobalMemoryStatusEx`）。
  CPU 为两次采样之间 idle/kernel/user 差值得到的整机占用率（与 macOS `host_statistics`
  差值思路一致）。刻意避开 `System.Diagnostics.PerformanceCounter`：它依赖（有时损坏或
  缺失的）Windows 性能计数器，且在某些机器上需要额外权限。
- **断网 / 无 CLI / 无数据时绝不伪造。** 每个服务只有在真正拿到应答时才返回标记为
  Available 的快照；其余路径都携带本地化键（如 `Msg_GhNotFound`、`Msg_Timeout`、
  `Msg_MacOSOnly_Harness`），卡片原样显示。
- **GitHub 仓库统计**来自 `gh api user/repos?per_page=100&affiliation=owner`
  （与 macOS 相同查询），因此最多覆盖 100 个 owner 仓库。
- **MakerWorld 设计详情**每次刷新最多拉取 4 个，保证 30 秒周期依然灵敏；聚合计数
  （`designCount`、下载、打印）来自主页的 `MWCount` 块，与 macOS 完全一致。

## 故障排查

- **XAML / 命名空间相关的构建错误**：先执行 `dotnet restore`；确认已安装 .NET 8 SDK 的
  Windows 桌面工作负载（`dotnet workload list`）。
- **天气卡片显示 “WebView2 Runtime is required…”**：安装 Evergreen WebView2 Runtime 并
  重启应用（见“环境要求”）。
- **天气卡片显示 “Could not load the earth map…”**：当前离线或 earth.nullschool.net
  不可达；网络恢复后点击 **Retry**。其余卡片此时会显示各自的 Unavailable 原因。
- **GitHub 卡片显示 gh 错误**：运行 `gh auth login`；确认 `gh` 在 `PATH` 中
  （新终端里执行 `gh --version`）且机器可访问网络。
- **Settings 设置后 MakerWorld 卡片仍不可用**：请确认 ID 是主页 URL 中的纯数字，且机器
  能访问 `api.bambulab.com`。
- **设计上就不造假**：拿不准时，卡片会明确告诉你它为什么无法显示数据，而不是猜测。
