> 🌏 [English](README.md) · **简体中文**

# Fusion Workbench — 实时数据看板

一个面向你电脑上正在运行的各种服务与数据的实时、可缩放看板：

**macOS 应用（SwiftUI / 液态玻璃）** —— 灵活画布上的 7 张玻璃卡片：
- **DeepSeek Harness** —— 本机 Harness 的实时状态（会话元数据 + 本地成本账本）
- **Codex** —— 本机 Codex 智能体服务的进行中任务与速率用量
- **Command Code** —— 本机 Command Code 应用状态（账号、版本）
- **GitHub** —— 通过 GitHub CLI（`gh`）读取的账号概览
- **MakerWorld** —— 你的 Bambu Lab / MakerWorld 主页概览（公开 API）
- **Mac 实时状态** —— CPU / 内存 / 磁盘 / GPU 占用
- **Nullschool 地球天气** —— 实时风场与天气图（WebView）

每张卡片都是真正的“活排版”：字体与间距随卡片缩放、内容纵向撑满整卡、字形永不压扁
或拉伸。你可以显示/隐藏卡片、拖动、缩放、缩放画布、自适应摆放与“适应全部”。

**Windows 应用（.NET 8 / WPF）** —— 同样的 7 张卡片的完整移植位于
[`windows/`](windows/README.zh-CN.md)。macOS 专属数据源（Harness / Codex / Command Code）
在 Windows 上会明确显示 **不可用（Unavailable）** 并说明原因，绝不造假数据。

---

## ⚠️ 请先阅读：这是 AI 构建的模板，不是成品

本仓库**不是开箱即用、可直接上生产的完整仪表盘**。它由 **AI 编程智能体**设计、编写并
持续维护，也请以同样的方式使用它：

- 克隆下来后，把它交给 AI 编程助手，请它针对你自己的电脑、账号与数据源进行适配。
- 一切皆可修改：加模块、换数据源、改卡片样式、改语言文案、加图表。
- 有些功能（液态玻璃、活排版）是刻意追求上限的尝试，请把它当作起点，并预期需要和 AI
  一起反复迭代。
- 数据绝不伪造：当某个数据源不可达或未配置时，卡片会显示 **不可用（Unavailable）** 并
  说明原因。

## 功能

- **中英双语界面** —— 默认英文，可通过画布工具栏（macOS）或窗口工具栏（Windows）上的
  开关切换到中文。
- **真实数据** —— 每张卡片都报告真实的本地/网络状态；拿不到数据就明确显示 Unavailable
  与原因，绝不编造数字。
- **液态玻璃（macOS 26）** —— 真正的玻璃卡片，采样透明窗口背后的内容。
- **灵活的活排版画布** —— 拖动、缩放、画布缩放、自适应摆放、适应全部；卡片文字随卡片
  等比缩放（系数限制在 0.45×–2×）。
- **默认注重隐私** —— 只读取本机非敏感元数据（会话标题、时间戳、聚合成本）。绝不读取
  密钥、凭据与会话正文。

## 仓库结构

```
├─ Package.swift              macOS 应用（Swift Package，SwiftUI）
├─ Sources/FusionWorkbench/   macOS 源码（7 个模块 + 采样器 + 本地化）
├─ Tests/                     macOS 单元测试
├─ windows/                   Windows 移植（.NET 8 / WPF）+ 其自身 README
└─ scripts/build-macos-app.sh 把 macOS 应用打包成 .app
```

## macOS —— 构建与运行

环境要求：**macOS 26 及以上**（液态玻璃 API）、**Xcode 26**（Swift 6.2 工具链）。

```bash
swift build -c release          # 构建可执行文件
./scripts/build-macos-app.sh    # 生成 dist/Fusion Workbench.app（临时签名）
open "dist/Fusion Workbench.app"
```

单元测试：`swift test`。

## Windows —— 构建与运行

见 [`windows/README.zh-CN.md`](windows/README.zh-CN.md)：环境要求（.NET SDK 8）、构建步骤
以及各卡片的数据源可用性对照表。

## 配置

| 数据源 | 你需要准备什么 | 缺失时 |
| --- | --- | --- |
| Harness（macOS） | 已安装 DeepSeek Harness 桌面端，数据位于 `~/.dsh` | 卡片显示 Unavailable |
| Codex（macOS） | 本机 ChatGPT.app 内含 Codex CLI | 卡片显示 Unavailable |
| Command Code（macOS） | 已安装 Command Code 应用 | 卡片显示 Unavailable |
| GitHub | 已安装并登录 GitHub CLI（`brew install gh`、`gh auth login`） | 卡片显示 Unavailable + 安装提示 |
| MakerWorld | 你的 MakerWorld 主页 ID | 卡片显示 Unavailable + 设置提示 |
| 系统 | 无需准备 | — |
| Nullschool 地球图 | 可访问网络（WebView） | 卡片内显示浏览器错误 |

### 设置你的 MakerWorld 主页 ID

出于隐私，原版本中的个人 MakerWorld ID 已被移除。请指向你自己的主页：

```bash
defaults write com.fusionworkbench.dashboard makerWorldUserID -int 你的ID
```

（Windows：在应用的 Settings 字段中填写。）

## 本地化

代码文案以英文书写；中文翻译位于
`Sources/FusionWorkbench/Localization.swift`。缺少的键会自动回退到英文，因此新增模块也能
天然保持双语安全。修改文案时，请同步更新表中的对应条目。

## 隐私与来源

本公开仓库是个人私有项目的“清洗后、以英文为主”的再发布版。个人标识（主页 ID、本地路径、
用户名、历史记录）已移除，git 历史特意全新开始。Windows 移植是对 macOS 各模块的源码级
移植；它无法在 macOS 上编译，编写时尽量保守，目标是用标准 .NET 8 SDK 即可构建。请在
Windows 机器上反馈问题。

## 反馈

欢迎提 Issue、想法与模块需求——请把这个仓库当作一个活的模板。
