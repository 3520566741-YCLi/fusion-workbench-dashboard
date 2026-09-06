# 用你自己的 AI 来个性化配置 Fusion Workbench

Fusion Workbench 是一个**框架**，不是成品。推荐用法是：下载 → 交给你自己
的 AI 编程助手 → 让它按*你的*电脑、账号与数据源做全部适配。

本文件告诉你如何安全、快速地做到这一点——macOS 版与 Windows 版都适用。

---

## 1. 下载

- **整个仓库（两个版本）**：GitHub 页面 **Code ▾ → Download ZIP**，或
  `git clone https://github.com/3520566741-YCLi/fusion-workbench-dashboard.git`
- macOS 应用是仓库根目录的 Swift Package（`Sources/FusionWorkbench/`）；
  Windows 应用在 `windows/`。
- 构建说明：根目录 `README.zh-CN.md`（macOS）与 `windows/README.zh-CN.md`
  （Windows）。

## 2. 告诉你的 AI 助手要做什么

本项目中**没有任何个人数据**——所有数据源要么留空等待你填写，要么读取
macOS/Windows 本机状态。把仓库交给 AI 编程智能体（Claude Code、Codex、
DeepSeek Harness、Gemini CLI……），并附上类似这样的需求：

> “我下载了 Fusion Workbench 看板，请帮我适配：
> 1. 先读 README 和各模块的采样器 / 服务代码。
> 2. 把空置/占位的数据源换成我的：
>    - GitHub → 用我的 `gh` 登录（或我给你的 token）
>    - MakerWorld → 填我的数字用户 ID
>    - 系统指标 → 保留，并确认它正确读取我的机器
>    - 我不用、且仅 macOS 有的数据源（Harness / Codex / Command Code）→
>      隐藏该卡片，或指向我确实有的真实数据源
> 3. 遵守“不造假数据”规则：拿不到就显示 Unavailable，绝不编数字。
> 4. UI 语言：保留英文默认与中文切换。
> 5. 帮我构建并修复编译错误，然后给我截图。”

务必告诉它**你用的是哪个系统**，并把需要的**报错输出**贴给它。

## 3. 给 AI 的隐私规则

- 绝不要把个人 ID、token 或路径硬编码进代码。敏感信息放进应用的
  Settings / `UserDefaults` / 环境变量——不要放进你可能再次公开的文件里。
- macOS 版 MakerWorld ID 从 `makerWorldUserID` 用户默认项读取（见根 README）；
  Windows 版在 Settings 中保存。
- 如果你发布自己的 fork，推送前先扫描你的名字、邮箱、ID 与 `~/.` 路径
  （见根 README 中 “隐私与来源”一节）。

## 4. 常见个性化指令示例

macOS：
- “新增一个 X 模块卡片，调用 Y 数据源——请遵循 `LiveLayout.swift` 的活排版
  约定，让文字像其他卡片一样随卡片缩放。”
- “把 System 卡片改成同时显示网络吞吐。”
- “让 GitHub 卡片指向我所在组织的仓库。”
- “在 `Localization.swift` 里补上我漏掉的中文文案。”

Windows：
- “把 Windows WPF 版的 GitHub 卡片改成使用我提供的 token，而不是 `gh` CLI。”
- “帮我在我的机器上修复构建错误 <粘贴报错>（Windows 11，.NET SDK 8）。”
- “参照现有卡片模式，给我的游戏服务器 API 加一张卡片。”

## 5. 保持它始终可用

- macOS：务必用 `swift build`、`swift test` 验证，再运行应用并截图
  （两种语言都截）。
- Windows：务必用 `dotnet build FusionWorkbench.sln -c Release` 验证并运行一次，
  两种语言都截图。
- 数据源失败时，卡片必须显示 **Unavailable + 原因**——绝不显示示例/伪造数据。
