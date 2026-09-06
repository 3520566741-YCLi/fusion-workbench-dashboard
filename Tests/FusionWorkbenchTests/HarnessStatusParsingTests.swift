import XCTest
@testable import FusionWorkbench

/// 针对 DeepSeek Harness 本地数据（~/.dsh）解析的最小测试。
/// 夹具结构镜像真实文件（storages/cost-meter/ledger.json 与
/// storages/session_projcache/sessions/*.json 的投影缓存），数值全部为脱敏样例。
final class HarnessStatusParsingTests: XCTestCase {

    // MARK: - 成本账本

    func testCostLedgerAggregatesTodayAndWeek() throws {
        let now = fixedNow()
        let todayKey = dayKey(for: now)
        let mondayKey = dayKey(for: monday(before: now))

        let json = ledgerJSON(daysJSON: """
        {
          "2026-08-29": \(dayEntry("2026-08-29", cost: 7.0)),
          "\(mondayKey)": \(dayEntry(mondayKey, cost: 0.5)),
          "2026-09-03": \(dayEntry("2026-09-03", cost: 2.0)),
          "\(todayKey)": \(dayEntry(todayKey, cost: 0.25))
        }
        """)

        let summary = HarnessStatusSampler.parseCostLedger(Data(json.utf8), now: now)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.symbol, "¥")
        XCTAssertEqual(summary?.decimals, 4)
        XCTAssertEqual(summary?.todayCost ?? -1, 0.25, accuracy: 1e-9)
        // 本周（周一至今日）= 0.5 + 2.0 + 0.25；上周日 7.0 不计入。
        XCTAssertEqual(summary?.weekCost ?? -1, 2.75, accuracy: 1e-9)
        XCTAssertEqual(summary?.formatted(summary?.todayCost), "¥0.2500")
    }

    func testCostLedgerUsesDefaultsWhenConfigMissing() throws {
        let json = """
        { "version": 1, "days": { "2026-09-01": { "cost": 3.5 } } }
        """
        let summary = HarnessStatusSampler.parseCostLedger(Data(json.utf8))
        XCTAssertEqual(summary?.symbol, "¥")
        XCTAssertEqual(summary?.decimals, 4)
    }

    func testCostLedgerEmptyOrCorruptReturnsNil() {
        // 账本不存在（nil 数据）由调用方处理；这里覆盖空 days 与 JSON 损坏。
        XCTAssertNil(HarnessStatusSampler.parseCostLedger(Data("{}".utf8)))
        XCTAssertNil(HarnessStatusSampler.parseCostLedger(Data(#"{ "days": {} }"#.utf8)))
        XCTAssertNil(HarnessStatusSampler.parseCostLedger(Data("not-json-{{".utf8)))
        XCTAssertNil(HarnessStatusSampler.parseCostLedger(Data(#"{ "days": [] }"#.utf8)))
    }

    func testCostLedgerConvertsUSDByExchangeRate() throws {
        let now = fixedNow()
        let todayKey = dayKey(for: now)
        let json = """
        {
          "version": 1,
          "config": { "currency": "CNY", "symbol": "¥", "decimals": 2, "pricingCurrency": "USD", "exchangeRate": 7.0 },
          "days": { "\(todayKey)": { "date": "\(todayKey)", "cost": 1.5 } }
        }
        """
        let summary = HarnessStatusSampler.parseCostLedger(Data(json.utf8), now: now)
        XCTAssertEqual(summary?.todayCost ?? -1, 10.5, accuracy: 1e-9)
        XCTAssertEqual(summary?.weekCost ?? -1, 10.5, accuracy: 1e-9)
        XCTAssertEqual(summary?.symbol, "¥")
        XCTAssertEqual(summary?.decimals, 2)
        XCTAssertEqual(summary?.formatted(summary?.todayCost), "¥10.50")
        XCTAssertEqual(summary?.convertedFromUSD, true)
    }

    // MARK: - 会话投影

    func testSessionProjectionParsesMetadataOnly() throws {
        let data = Data(activeSessionJSON.utf8)
        let session = HarnessStatusSampler.parseSessionProjection(data, id: "session-abc")

        XCTAssertNotNil(session)
        XCTAssertEqual(session?.title, "示例任务标题")
        XCTAssertEqual(session?.provider, "deepseek-official")
        XCTAssertEqual(session?.model, "deepseek-v4-flash")
        let expected = Date(timeIntervalSince1970: 1_788_624_063.022)
        XCTAssertEqual(session?.updatedAt?.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 1e-6)
    }

    func testSessionProjectionSkipsBlankSessions() {
        XCTAssertNil(HarnessStatusSampler.parseSessionProjection(Data(blankSessionJSON.utf8), id: "session-blank"))
    }

    func testSessionProjectionToleratesCorruptData() {
        XCTAssertNil(HarnessStatusSampler.parseSessionProjection(Data("not-json-{{".utf8), id: "session-bad"))
        XCTAssertNil(HarnessStatusSampler.parseSessionProjection(Data(#"{ "unexpected": true }"#.utf8), id: "session-bad"))
    }

    // MARK: - 整目录采样

    func testReadSnapshotOnFixtureDirectory() throws {
        let now = fixedNow()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionsDir = root.appendingPathComponent("storages/session_projcache/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let activeMs = Int64(now.timeIntervalSince1970 * 1000) - 30_000
        let staleMs = Int64(now.timeIntervalSince1970 * 1000) - 3_600_000
        let active = sessionProjectionJSON(lastPromptAtMs: activeMs, title: "活跃任务 A")
        let stale = sessionProjectionJSON(lastPromptAtMs: staleMs, title: "旧任务 B")
        try Data(active.utf8).write(to: sessionsDir.appendingPathComponent("session-active.json"))
        try Data(stale.utf8).write(to: sessionsDir.appendingPathComponent("session-stale.json"))

        let todayKey = dayKey(for: now)
        let mondayKey = dayKey(for: monday(before: now))
        let ledger = ledgerJSON(daysJSON: """
        { "\(mondayKey)": \(dayEntry(mondayKey, cost: 1.0)), "\(todayKey)": \(dayEntry(todayKey, cost: 2.0)) }
        """)
        let meterDir = root.appendingPathComponent("storages/cost-meter", isDirectory: true)
        try FileManager.default.createDirectory(at: meterDir, withIntermediateDirectories: true)
        try Data(ledger.utf8).write(to: meterDir.appendingPathComponent("ledger.json"))

        let snapshot = HarnessStatusSampler.readSnapshot(dataDirectory: root, now: now, appIsRunning: false)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertFalse(snapshot.isRunning)
        XCTAssertEqual(snapshot.activeSessionCount, 1) // 只有最近 30 秒的会话算活跃
        XCTAssertEqual(snapshot.recentSessions.count, 2)
        XCTAssertEqual(snapshot.recentSessions.first?.title, "活跃任务 A")
        XCTAssertEqual(snapshot.provider, "deepseek-official")
        XCTAssertEqual(snapshot.model, "deepseek-v4-flash")
        XCTAssertEqual(snapshot.cost?.todayCost ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(snapshot.cost?.weekCost ?? -1, 3.0, accuracy: 1e-9)
    }

    func testReadSnapshotToleratesMissingLedgerAndSessions() throws {
        let now = fixedNow()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let snapshot = HarnessStatusSampler.readSnapshot(dataDirectory: root, now: now, appIsRunning: false)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertNil(snapshot.cost) // 无账本 -> “暂无本地成本数据”
        XCTAssertTrue(snapshot.recentSessions.isEmpty)
        XCTAssertEqual(snapshot.activeSessionCount, 0)
    }

    func testReadSnapshotToleratesMissingDataDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-missing-\(UUID().uuidString)", isDirectory: true)
        let snapshot = HarnessStatusSampler.readSnapshot(dataDirectory: missing)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertNil(snapshot.cost)
    }

    // MARK: - 自适应摆放

    @MainActor
    func testAutoArrangePacksWithoutOverlapAndRespectsBounds() throws {
        let store = FusionStore()
        store.resetDashboardLayout()
        store.autoArrange(in: CGSize(width: 1420, height: 860))

        let items = store.dashboardLayout.filter(\.isVisible)
        XCTAssertEqual(items.count, DashboardLayoutItem.defaults.filter(\.isVisible).count)
        for item in items {
            XCTAssertGreaterThanOrEqual(item.x, 0)
            XCTAssertGreaterThanOrEqual(item.y, 0)
            XCTAssertGreaterThan(item.width, 0)
            XCTAssertGreaterThan(item.height, 0)
            XCTAssertLessThanOrEqual(item.x + item.width, DashboardCanvasLimits.columns)
            XCTAssertLessThanOrEqual(item.y + item.height, DashboardCanvasLimits.rows)
            let minimum = item.id.minimumSize
            XCTAssertGreaterThanOrEqual(item.width, minimum.width)
            XCTAssertGreaterThanOrEqual(item.height, minimum.height)
        }
        for (index, left) in items.enumerated() {
            for right in items.dropFirst(index + 1) {
                let overlaps = left.x < right.x + right.width && left.x + left.width > right.x
                    && left.y < right.y + right.height && left.y + left.height > right.y
                XCTAssertFalse(overlaps, "\(left.id) 与 \(right.id) 重叠")
            }
        }
    }

    // MARK: - 夹具

    private func fixedNow() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12, minute: 0))!
    }

    private func monday(before date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let weekday = calendar.component(.weekday, from: date) // 1 = 周日 … 7 = 周六
        let back = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: date))!
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func ledgerJSON(daysJSON: String) -> String {
        """
        {
          "version": 1,
          "config": { "locale": "zh", "currency": "CNY", "symbol": "¥", "decimals": 4, "pricingCurrency": "USD" },
          "days": \(daysJSON),
          "migrations": [],
          "balanceRef": { "date": "2026-09-05", "total": 96.84, "granted": 0, "topped": 96.84, "currency": "CNY" },
          "planHourBuckets": {},
          "planSamples": {}
        }
        """
    }

    private func dayEntry(_ key: String, cost: Double) -> String {
        """
        { "date": "\(key)", "input": 100, "output": 50, "cacheRead": 0, "cacheWrite": 0, "reasoning": 0, "calls": 2, "cost": \(cost), "apiCost": \(cost), "byProviderModel": {}, "sessions": [] }
        """
    }

    /// 结构与真实会话投影一致：record.rows.<key>.val 包装。
    private func sessionProjectionJSON(lastPromptAtMs: Int64, title: String) -> String {
        """
        {
          "version": 1,
          "record": {
            "identity": { "createdAt": 1788623965140, "cwd": "/tmp", "isSeeded": false, "inheritedEventCount": 0 },
            "rows": {
              "sessionListMetadata": { "ver": 1, "seq": 1, "val": { "blank": false, "lastPromptAt": \(lastPromptAtMs) } },
              "title": { "ver": 1, "seq": 2, "val": "\(title)" },
              "modelSelection": { "ver": 1, "seq": 3, "val": { "lastUsed": { "provider": "deepseek-official", "model": "deepseek-v4-flash", "reasoningEffort": "high" }, "pending": null } },
              "costUsage": { "ver": 1, "seq": 4, "val": { "provider": "deepseek-official", "model": "deepseek-v4-flash" } }
            }
          }
        }
        """
    }

    private var activeSessionJSON: String {
        sessionProjectionJSON(lastPromptAtMs: 1_788_624_063_022, title: "示例任务标题")
    }

    private var blankSessionJSON: String {
        """
        {
          "version": 1,
          "record": {
            "identity": { "createdAt": 1788423998571, "cwd": "/tmp", "isSeeded": false, "inheritedEventCount": 0 },
            "rows": {
              "sessionListMetadata": { "ver": 1, "seq": 1, "val": { "blank": true, "lastPromptAt": null } }
            }
          }
        }
        """
    }
}
