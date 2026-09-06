import Foundation

struct CommandCodeStatusSnapshot: Equatable, Sendable {
    let isConnected: Bool
    let message: String
    let authenticatedUser: String?
    let version: String?
    let sampledAt: Date

    static let unavailable = CommandCodeStatusSnapshot(
        isConnected: false,
        message: "Checking the local Command Code status…",
        authenticatedUser: nil,
        version: nil,
        sampledAt: .now
    )
}

struct CommandCodeStatusSampler: Sendable {
    private static let cliPath = "/Applications/Command Code.app/Contents/Resources/app/node_modules/command-code/dist/index.mjs"

    func sample() async -> CommandCodeStatusSnapshot {
        await Task.detached(priority: .utility) { Self.readSnapshot() }.value
    }

    private static func readSnapshot() -> CommandCodeStatusSnapshot {
        guard FileManager.default.fileExists(atPath: cliPath) else {
            return unavailable("Command Code app not found")
        }
        guard let node = Self.nodePath() else {
            return unavailable("Node.js runtime not found")
        }

        let status = run(executable: node, args: [cliPath, "status"])
        let version = run(executable: node, args: [cliPath, "--version"])

        let user = parseUser(from: status)
        let appVersion = parseVersion(from: version)

        guard user != nil || appVersion != nil else {
            return unavailable("Command Code service is temporarily unavailable")
        }
        return CommandCodeStatusSnapshot(
            isConnected: true,
            message: "Local Command Code connected.",
            authenticatedUser: user,
            version: appVersion,
            sampledAt: .now
        )
    }

    private static func nodePath() -> String? {
        let candidates = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private static func run(executable: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func parseUser(from output: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: "Authenticated as\\s+([^\\s]+)"),
              let match = expression.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }

    private static func parseVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.range(of: #"^\d+(\.\d+){1,3}$"#, options: .regularExpression) != nil else { return nil }
        return trimmed
    }

    private static func unavailable(_ message: String) -> CommandCodeStatusSnapshot {
        CommandCodeStatusSnapshot(isConnected: false, message: message, authenticatedUser: nil, version: nil, sampledAt: .now)
    }
}
