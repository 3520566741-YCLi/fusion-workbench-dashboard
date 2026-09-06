import Foundation

struct CodexUsageWindow: Equatable, Sendable {
    let usedPercent: Int
    let resetsAt: Date?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
}

struct CodexTaskStatus: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let updatedAt: Date?
    let needsAttention: Bool
}

struct CodexStatusSnapshot: Equatable, Sendable {
    let isConnected: Bool
    let message: String
    let usageMessage: String?
    let runningTasks: [CodexTaskStatus]
    let fiveHourUsage: CodexUsageWindow?
    let weeklyUsage: CodexUsageWindow?
    let sampledAt: Date

    static let unavailable = CodexStatusSnapshot(
        isConnected: false,
        message: "Connecting to the local Codex service…",
        usageMessage: nil,
        runningTasks: [],
        fiveHourUsage: nil,
        weeklyUsage: nil,
        sampledAt: .now
    )
}

struct CodexStatusSampler: Sendable {
    private static let executable = "/Applications/ChatGPT.app/Contents/Resources/codex"

    func sample() async -> CodexStatusSnapshot {
        await Task.detached(priority: .utility) { Self.readSnapshot() }.value
    }

    private static func readSnapshot() -> CodexStatusSnapshot {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return unavailable("Local Codex service not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let writer = input.fileHandleForWriting
            // 边读边解析：等 thread/list（任务）与 account/rateLimits（用量）两个结果都到达
            // （或 15 秒超时）。用量接口常需要数秒才返回，固定短等待会把它漏掉。
            let collector = CodexOutputCollector()
            let semaphore = DispatchSemaphore(value: 0)
            let handle = output.fileHandleForReading
            handle.readabilityHandler = { readHandle in
                let chunk = readHandle.availableData
                if chunk.isEmpty {
                    readHandle.readabilityHandler = nil
                    semaphore.signal()
                    return
                }
                collector.append(chunk)
                if collector.hasAllResponses {
                    readHandle.readabilityHandler = nil
                    semaphore.signal()
                }
            }

            write(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "fusion-workbench", "version": "1.0"]]], to: writer)
            Thread.sleep(forTimeInterval: 1)
            write(["method": "initialized", "params": [:]], to: writer)
            write(["id": 2, "method": "thread/list", "params": ["archived": false, "limit": 30]], to: writer)
            write(["id": 3, "method": "account/rateLimits/read", "params": NSNull()], to: writer)
            _ = semaphore.wait(timeout: .now() + 15)
            handle.readabilityHandler = nil
            try? writer.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            return parse(collector.snapshot())
        } catch {
            return unavailable("Local Codex service is temporarily unavailable")
        }
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static func parse(_ data: Data) -> CodexStatusSnapshot {
        var tasks = [CodexTaskStatus]()
        var primary: CodexUsageWindow?
        var secondary: CodexUsageWindow?
        var connected = false

        for line in data.split(separator: 10) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? Int,
                  let result = object["result"] as? [String: Any] else { continue }
            connected = true
            if id == 2, let entries = result["data"] as? [[String: Any]] {
                tasks = entries.compactMap(task(from:)).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            }
            if id == 3, let limits = rateLimits(from: result) {
                primary = usage(from: limits["primary"])
                secondary = usage(from: limits["secondary"])
            }
        }

        return CodexStatusSnapshot(
            isConnected: connected,
            message: connected ? "Local Codex connected." : "Local Codex service is temporarily unavailable",
            usageMessage: connected && primary == nil && secondary == nil ? "The usage API returned no data" : nil,
            runningTasks: tasks,
            fiveHourUsage: primary,
            weeklyUsage: secondary,
            sampledAt: .now
        )
    }

    private static func task(from entry: [String: Any]) -> CodexTaskStatus? {
        guard let status = entry["status"] as? [String: Any], status["type"] as? String == "active",
              let id = entry["id"] as? String else { return nil }
        let flags = Set(status["activeFlags"] as? [String] ?? [])
        return CodexTaskStatus(
            id: id,
            title: (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled Codex task",
            updatedAt: (entry["updatedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)),
            needsAttention: flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput")
        )
    }

    private static func usage(from value: Any?) -> CodexUsageWindow? {
        guard let value = value as? [String: Any], let usedPercent = integer(value["usedPercent"]) else { return nil }
        return CodexUsageWindow(
            usedPercent: usedPercent,
            resetsAt: integer(value["resetsAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func rateLimits(from result: [String: Any]) -> [String: Any]? {
        if let limits = result["rateLimits"] as? [String: Any] { return limits }
        guard let byLimitID = result["rateLimitsByLimitId"] as? [String: Any] else { return nil }
        return (byLimitID["codex"] as? [String: Any])
            ?? byLimitID.values.compactMap { $0 as? [String: Any] }.first
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func unavailable(_ message: String) -> CodexStatusSnapshot {
        CodexStatusSnapshot(isConnected: false, message: message, usageMessage: nil, runningTasks: [], fiveHourUsage: nil, weeklyUsage: nil, sampledAt: .now)
    }
}

/// 线程安全地累积 Codex 输出，并判断任务/用量两个目标响应是否都已到达。
private final class CodexOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var sawThreads = false
    private var sawLimits = false

    var hasAllResponses: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sawThreads && sawLimits
    }

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        if !sawThreads { sawThreads = containsResponse(id: 2) }
        if !sawLimits { sawLimits = containsResponse(id: 3) }
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    private func containsResponse(id: Int) -> Bool {
        for line in data.split(separator: 10) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["id"] as? Int == id,
                  object["result"] != nil else { continue }
            return true
        }
        return false
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
