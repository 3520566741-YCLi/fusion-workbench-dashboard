// Fusion Workbench — Localization.swift
//
// Lightweight runtime English ⇄ 中文 switching for the public (bilingual)
// build. English is the default language and also the language the source
// code is written in; Chinese copy lives only in the `zhTable` below.
//
// Mechanism: the whole dashboard is rebuilt under a new `.id(language)`
// whenever the toolbar toggle changes, so every `tr(...)` call re-evaluates
// against the latest preference. Unknown keys fall back to English, which
// keeps future modules bilingual-safe by default.

import Foundation

enum AppLanguage {
    static let defaultsKey = "appLanguage"

    /// True only when the user explicitly chose Chinese.
    static var isChinese: Bool {
        UserDefaults.standard.string(forKey: defaultsKey) == "zh"
    }

    /// Stable tag used to force a full dashboard rebuild on language change.
    static var current: String {
        isChinese ? "zh" : "en"
    }
}

/// Pick the translation for the current UI language.
func tr(_ key: String) -> String {
    guard AppLanguage.isChinese, let zh = zhTable[key] else { return key }
    return zh
}

/// Variant with one integer placeholder written `{n}`.
func tr(_ key: String, _ n: Int) -> String {
    tr(key).replacingOccurrences(of: "{n}", with: "\(n)")
}

/// Variant with two integer placeholders `{n}` and `{m}`.
func tr(_ key: String, _ n: Int, _ m: Int) -> String {
    tr(key)
        .replacingOccurrences(of: "{n}", with: "\(n)")
        .replacingOccurrences(of: "{m}", with: "\(m)")
}

/// Variant with one string placeholder written `{s}`.
func tr(_ key: String, _ s: String) -> String {
    tr(key).replacingOccurrences(of: "{s}", with: s)
}

// English key → 简体中文. Keys missing here simply stay English.
private let zhTable: [String: String] = [
    // Workspace chrome
    "Component Library": "组件库",
    "Collapse Library": "收起组件库",
    "Expand Library": "展开组件库",
    "Modules": "组件",
    "Show or Hide Canvas Modules · {n} / {m}": "显示或隐藏画布模块 · {n} / {m}",
    "Reset Default Layout": "恢复默认布局",
    "Edit Layout": "编辑布局",
    "Finish Layout": "完成布局",
    "Auto Layout": "自适应布局",
    "Auto Arrange": "自适应摆放",
    "Fit All": "适应全部",
    "Rearranges cards into full rows following your current reading order (top → bottom, left → right) and fills the whole window.": "按你当前摆放的阅读顺序（上→下、左→右）自动重排并铺满整个窗口",
    "Rearranges and resizes cards by their aspect ratio to fill the current view.": "按卡片比例自动重排并调整大小，铺满当前画面",
    "Only zooms and pans; keeps the current arrangement.": "只缩放与平移，保持当前排列",
    "Switch between English and Chinese": "切换中英文",

    // Module titles
    "Nullschool Earth Weather": "Nullschool 地球天气",
    "Live Wind and Weather Map": "实时风场与天气图",
    "Mac Status": "Mac 实时状态",
    "Codex Status": "Codex 实时状态",
    "Command Code Status": "Command Code 实时状态",
    "GitHub Overview": "GitHub 账号概览",
    "MakerWorld Overview": "MakerWorld 账号概览",
    "DeepSeek Harness Status": "DeepSeek Harness 实时状态",

    // System module
    "Monitoring": "监控中",
    "Paused": "已暂停",
    "Waiting for the First Sample…": "正在等待首次采样…",
    "Sampling": "采样中",
    "Updated {s}": "更新于 {s}",
    "Memory": "内存",
    "Disk": "磁盘",
    "Available {s}": "可用 {s}",
    "GPU": "GPU",
    "GPU · {n} Cores": "GPU · {n} 核",
    "Device {s}": "设备 {s}",

    // Codex module
    "Last 5 Hours": "5 小时用量",
    "This Week": "本周用量",
    "Reading": "正在读取",
    "Running": "运行中",
    "Needs Your Confirmation": "需要你确认",
    "Connected": "已连接",
    "Unavailable": "暂不可用",
    "Remaining {n}%": "剩余 {n}%",
    "Used {n}%": "已用 {n}%",
    "Resets at {s}": "重置于 {s}",

    // Command Code module
    "Signed-in Account": "登录账号",
    "App Version": "应用版本",
    "Usage & Subscription": "用量与订阅",
    "Command Code does not expose an automatic read API — check usage, remaining quota and subscription expiry inside Command Code with /usage.": "Command Code 未提供自动读取接口：用量、剩余额度与订阅到期时间请到 Command Code 内查看 /usage。",

    // GitHub module
    "Account": "账号",
    "Member Since": "注册时间",
    "Public Repos": "公开仓库",
    "Private Repos": "私有仓库",
    "Total Repos": "仓库总数",
    "Forks": "分叉",
    "Recently Updated": "最近更新",

    // MakerWorld module
    "Followers": "粉丝",
    "Following": "关注",
    "Likes": "获赞",
    "Collections": "收藏",
    "Models": "模型数",
    "Downloads": "模型下载",
    "Prints": "模型打印",
    "Model List": "模型列表",
    "Recently Updated Models": "最近更新模型",

    // Harness module
    "Model / Provider": "模型 / Provider",
    "API Balance / Quota": "API 余额 / 额度",
    "Check your balance on the DeepSeek console": "余额请到 DeepSeek 控制台查看",
    "No Local Cost Data Yet": "暂无本地成本数据",
    "Active Sessions": "活跃会话",
    "Today's Cost": "今日成本",
    "This Week's Cost": "本周成本",
    "Recent Tasks": "最近任务",
    "Online": "在线",
    "Not Running": "未运行",
    "Reads only local non-sensitive metadata — never keys or conversation content.": "仅读取本机非敏感元数据 · 不读取密钥与会话正文",
    "Ledger costs are recorded in USD and converted to ¥ at the ledger exchange rate · only non-sensitive metadata is read.": "账本按 USD 计费，已按汇率折算为 ¥ · 仅读取非敏感元数据",

    // Status messages produced by samplers (shown through tr(status.message))
    "Connecting to the local Codex service…": "正在连接本机 Codex 服务",
    "Local Codex service not found": "未找到本机 Codex 服务",
    "Local Codex service is temporarily unavailable": "本机 Codex 服务暂不可用",
    "Local Codex connected.": "本机 Codex 已连接",
    "The usage API returned no data": "用量接口未返回数据",
    "Checking the local Command Code status…": "正在检查本机 Command Code 状态",
    "Command Code app not found": "未找到 Command Code 应用",
    "Node.js runtime not found": "未找到 Node.js 运行时",
    "Command Code service is temporarily unavailable": "Command Code 服务暂不可用",
    "Local Command Code connected.": "本机 Command Code 已连接",
    "Checking GitHub CLI login status…": "正在检查本机 GitHub 登录状态",
    "GitHub CLI (gh) not found — install it with: brew install gh": "未找到 GitHub CLI（gh），请先安装：brew install gh",
    "GitHub CLI is not logged in or the service is unavailable": "GitHub CLI 未登录或服务暂不可用",
    "GitHub CLI connected.": "本机 GitHub 已连接",
    "Connecting to MakerWorld…": "正在连接 MakerWorld",
    "MakerWorld user id is not set — configure makerWorldUserID (see README) to enable this card": "未设置 MakerWorld 用户 ID —— 配置 makerWorldUserID（见 README）后即可启用此卡片",
    "MakerWorld service is temporarily unavailable": "MakerWorld 服务暂不可用",
    "MakerWorld connected.": "MakerWorld 已连接",
    "Checking the local DeepSeek Harness…": "正在检查本机 DeepSeek Harness",
    "Harness data directory (~/.dsh) not found": "未找到 Harness 数据目录（~/.dsh）",
    "DeepSeek Harness is running": "DeepSeek Harness 正在运行",
    "DeepSeek Harness is online (no active sessions)": "DeepSeek Harness 在线（当前无活跃会话）",
    "The DeepSeek Harness desktop app is not running": "DeepSeek Harness 桌面端未在运行",
]
