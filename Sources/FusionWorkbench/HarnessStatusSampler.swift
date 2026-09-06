import AppKit
import Foundation

/// DeepSeek Harness 本地数据目录约定（只读取非敏感元数据，绝不读取凭据与会话正文）。
enum HarnessLocalLayout {
    static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dsh", isDirectory: true)
    static let sessionsRelativePath = "storages/session_projcache/sessions"
    static let costLedgerRelativePath = "storages/cost-meter/ledger.json"
    static let appBundleIdentifier = "ai.deepseek.dsh.desktop"
}

/// 一条 Harness 会话（任务）的公开元数据。
struct HarnessSessionStatus: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let provider: String?
    let model: String?
    let updatedAt: Date?
}

/// 本地成本账本中“今日 / 本周”的聚合摘要；账本缺失或结构不明时整体为 nil。
struct HarnessCostSummary: Equatable, Sendable {
    let symbol: String
    let decimals: Int
    let todayCost: Double?
    let weekCost: Double?
    /// 账本原始单位为 USD，且已按账本自带汇率折算为显示币种（¥）。
    let convertedFromUSD: Bool

    func formatted(_ amount: Double?) -> String? {
        guard let amount else { return nil }
        let digits = min(max(decimals, 0), 6)
        return "\(symbol)\(String(format: "%.\(digits)f", amount))"
    }
}

struct HarnessStatusSnapshot: Equatable, Sendable {
    let isAvailable: Bool
    let isRunning: Bool
    let message: String
    let provider: String?
    let model: String?
    let activeSessionCount: Int
    let recentSessions: [HarnessSessionStatus]
    let cost: HarnessCostSummary?
    let sampledAt: Date

    static let unavailable = HarnessStatusSnapshot(
        isAvailable: false,
        isRunning: false,
        message: "Checking the local DeepSeek Harness…",
        provider: nil,
        model: nil,
        activeSessionCount: 0,
        recentSessions: [],
        cost: nil,
        sampledAt: .now
    )
}

struct HarnessStatusSampler: Sendable {
    /// 会话超过该时长没有新提示即视为“非活跃”。
    static let activeWindow: TimeInterval = 15 * 60
    /// 数据心跳兜底：进程检测不到但数据仍在更新时仍视为运行中。
    static let heartbeatWindow: TimeInterval = 5 * 60

    func sample() async -> HarnessStatusSnapshot {
        let appIsRunning = Self.isHarnessAppRunning
        let directory = HarnessLocalLayout.dataDirectory
        return await Task.detached(priority: .utility) {
            Self.readSnapshot(dataDirectory: directory, now: .now, appIsRunning: appIsRunning)
        }.value
    }

    // MARK: - 读取

    /// 组装一次完整采样。文件缺失、JSON 损坏或目录不存在都不会抛错。
    static func readSnapshot(dataDirectory: URL, now: Date = .now, appIsRunning: Bool? = nil) -> HarnessStatusSnapshot {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dataDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return unavailable("Harness data directory (~/.dsh) not found")
        }

        let sessions = readSessions(from: dataDirectory.appendingPathComponent(HarnessLocalLayout.sessionsRelativePath, isDirectory: true))
        let cost = readCostLedger(from: dataDirectory.appendingPathComponent(HarnessLocalLayout.costLedgerRelativePath), now: now)
        let running = appIsRunning ?? (Self.isHarnessAppRunning || isHeartbeatFresh(sessions: sessions, now: now))

        let activeCount = sessions.filter { session in
            guard let updatedAt = session.updatedAt else { return false }
            return now.timeIntervalSince(updatedAt) <= Self.activeWindow
        }.count

        // 取最近一个有模型记录的会话作为“当前/最近使用的模型与 Provider”。
        let latest = sessions.first { $0.model != nil }
        let message: String
        if running {
            message = activeCount > 0 ? "DeepSeek Harness is running" : "DeepSeek Harness is online (no active sessions)"
        } else {
            message = "The DeepSeek Harness desktop app is not running"
        }

        return HarnessStatusSnapshot(
            isAvailable: true,
            isRunning: running,
            message: message,
            provider: latest?.provider,
            model: latest?.model,
            activeSessionCount: activeCount,
            recentSessions: Array(sessions.prefix(4)),
            cost: cost,
            sampledAt: now
        )
    }

    private static func readSessions(from directory: URL) -> [HarnessSessionStatus] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var sessions: [HarnessSessionStatus] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let session = parseSessionProjection(data, id: url.deletingPathExtension().lastPathComponent) {
                sessions.append(session)
            }
        }
        return sessions.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    private static func readCostLedger(from url: URL, now: Date) -> HarnessCostSummary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseCostLedger(data, now: now)
    }

    private static func isHeartbeatFresh(sessions: [HarnessSessionStatus], now: Date) -> Bool {
        guard let newest = sessions.first?.updatedAt else { return false }
        return now.timeIntervalSince(newest) <= Self.heartbeatWindow
    }

    // MARK: - 解析（内部静态方法，便于最小单元测试）

    /// 解析会话投影 JSON。只读取标题、最后提示时间与模型选择等元数据。
    /// 空会话（从未输入）与结构不符的数据返回 nil。
    static func parseSessionProjection(_ data: Data, id: String) -> HarnessSessionStatus? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = object["record"] as? [String: Any],
              let rows = record["rows"] as? [String: Any] else { return nil }

        let listMetadata = rowValue(rows, key: "sessionListMetadata")
        guard let blank = listMetadata?["blank"] as? Bool, !blank else { return nil }

        let lastPromptAt = number(listMetadata?["lastPromptAt"])
        guard let updatedAt = dateFromEpochMs(lastPromptAt) else { return nil }

        var provider: String?
        var model: String?
        if let lastUsed = rowValue(rows, key: "modelSelection")?["lastUsed"] as? [String: Any] {
            provider = lastUsed["provider"] as? String
            model = lastUsed["model"] as? String
        }
        if model == nil, let costUsage = rowValue(rows, key: "costUsage") {
            provider = provider ?? costUsage["provider"] as? String
            model = costUsage["model"] as? String
        }

        // title 行的 val 直接是字符串（与对象行不同），单独解包。
        let titleValue = (rows["title"] as? [String: Any])?["val"] as? String
        let title = titleValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled session"
        return HarnessSessionStatus(
            id: id,
            title: title.isEmpty ? "Untitled session" : title,
            provider: provider,
            model: model,
            updatedAt: updatedAt
        )
    }

    /// 解析成本账本 JSON。账本缺失、损坏或没有按日记录时返回 nil（调用方显示“暂无本地成本数据”）。
    static func parseCostLedger(_ data: Data, now: Date = .now) -> HarnessCostSummary? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = object["days"] as? [String: Any], !days.isEmpty else { return nil }

        let config = object["config"] as? [String: Any]
        let symbol = (config?["symbol"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "¥"
        let decimals = integer(config?["decimals"]) ?? 4
        // 账本原始单位是 pricingCurrency（通常 USD）；显示币种为 currency（¥）。
        // 两者不同且账本给出 exchangeRate 时按汇率折算，避免把 USD 数字直接标成 ¥。
        let pricingCurrency = config?["pricingCurrency"] as? String
        let currency = config?["currency"] as? String
        let exchangeRate = number(config?["exchangeRate"]) ?? 1
        let shouldConvert = exchangeRate > 0 && currency != nil && pricingCurrency != nil && pricingCurrency != currency
        let factor = shouldConvert ? exchangeRate : 1

        let formatter = dayKeyFormatter()
        let todayKey = formatter.string(from: now)
        guard let weekStart = calendar().date(byAdding: .day, value: -daysSinceMonday(from: now), to: calendar().startOfDay(for: now)) else {
            return nil
        }
        let weekStartKey = formatter.string(from: weekStart)

        var todayCost: Double?
        var weekCost: Double?
        for (key, value) in days where key.count == 10 && key <= todayKey && key >= weekStartKey {
            guard let entry = value as? [String: Any], let cost = double(entry["cost"]) else { continue }
            let converted = cost * factor
            weekCost = (weekCost ?? 0) + converted
            if key == todayKey { todayCost = converted }
        }
        return HarnessCostSummary(
            symbol: symbol,
            decimals: decimals,
            todayCost: todayCost,
            weekCost: weekCost,
            convertedFromUSD: shouldConvert
        )
    }

    // MARK: - 私有辅助

    /// Harness 桌面端进程检测（只读进程列表，无副作用、无需凭据）。
    private static var isHarnessAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: HarnessLocalLayout.appBundleIdentifier).isEmpty
    }

    private static func unavailable(_ message: String) -> HarnessStatusSnapshot {
        HarnessStatusSnapshot(
            isAvailable: false,
            isRunning: false,
            message: message,
            provider: nil,
            model: nil,
            activeSessionCount: 0,
            recentSessions: [],
            cost: nil,
            sampledAt: .now
        )
    }

    /// 投影缓存中的每一行是 { ver, seq, val } 包装，取其中的 val。
    private static func rowValue(_ rows: [String: Any], key: String) -> [String: Any]? {
        (rows[key] as? [String: Any])?["val"] as? [String: Any]
    }

    /// lastPromptAt / createdAt 为毫秒时间戳（约 1.7e12）；兼容秒级旧数据。
    private static func dateFromEpochMs(_ value: Double?) -> Date? {
        guard let value else { return nil }
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        number(value)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func dayKeyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// 返回本周一之前的自然天数（calendar.weekday：1=周日 … 7=周六）。
    private static func daysSinceMonday(from date: Date) -> Int {
        (calendar().component(.weekday, from: date) + 5) % 7
    }
}
