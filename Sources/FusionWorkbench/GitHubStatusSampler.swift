import Foundation

struct GitHubRepositoryInfo: Equatable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let isPrivate: Bool
    let isFork: Bool
    let language: String?
    let starCount: Int
    let updatedAt: Date?
}

struct GitHubStatusSnapshot: Equatable, Sendable {
    let isConnected: Bool
    let message: String
    let username: String?
    let accountCreatedAt: Date?
    let publicRepoCount: Int?
    let privateRepoCount: Int?
    let forkCount: Int?
    let organizations: [String]
    let recentRepositories: [GitHubRepositoryInfo]
    let sampledAt: Date

    var totalRepoCount: Int? {
        guard let publicRepoCount, let privateRepoCount else { return nil }
        return publicRepoCount + privateRepoCount
    }

    static let unavailable = GitHubStatusSnapshot(
        isConnected: false,
        message: "Checking GitHub CLI login status…",
        username: nil,
        accountCreatedAt: nil,
        publicRepoCount: nil,
        privateRepoCount: nil,
        forkCount: nil,
        organizations: [],
        recentRepositories: [],
        sampledAt: .now
    )
}

struct GitHubStatusSampler: Sendable {
    private static let ghPath = "/usr/bin/env"

    func sample() async -> GitHubStatusSnapshot {
        await Task.detached(priority: .utility) { Self.readSnapshot() }.value
    }

    private static func readSnapshot() -> GitHubStatusSnapshot {
        guard FileManager.default.isExecutableFile(atPath: ghPath) else {
            return unavailable("GitHub CLI (gh) not found — install it with: brew install gh")
        }

        let userJSON = run(ghPath, ["api", "user", "--jq", "{login, created_at, public_repos}"])
        let reposJSON = run(ghPath, ["api", "user/repos?per_page=100&affiliation=owner", "--jq", "[.[] | {name, private, fork, language, stargazers_count, updated_at}]"])
        let orgsJSON = run(ghPath, ["api", "user/orgs", "--jq", "[.[] | .login]"])

        guard let user = decodeUser(userJSON) else {
            return unavailable("GitHub CLI is not logged in or the service is unavailable")
        }

        let repos = decodeRepos(reposJSON)
        return GitHubStatusSnapshot(
            isConnected: true,
            message: "GitHub CLI connected.",
            username: user.login,
            accountCreatedAt: user.createdAt,
            publicRepoCount: user.publicRepos,
            privateRepoCount: repos.count(where: \.isPrivate),
            forkCount: repos.count(where: \.isFork),
            organizations: decodeOrgs(orgsJSON),
            recentRepositories: Array(repos.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }.prefix(4)),
            sampledAt: .now
        )
    }

    private static func run(_ executable: String, _ args: [String]) -> String {
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

    private struct UserDecoded {
        let login: String?
        let createdAt: Date?
        let publicRepos: Int?
    }

    private static func decodeUser(_ json: String) -> UserDecoded? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let createdAt = (object["created_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return UserDecoded(
            login: object["login"] as? String,
            createdAt: createdAt,
            publicRepos: object["public_repos"] as? Int
        )
    }

    private static func decodeRepos(_ json: String) -> [GitHubRepositoryInfo] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { object in
            guard let name = object["name"] as? String else { return nil }
            return GitHubRepositoryInfo(
                name: name,
                isPrivate: object["private"] as? Bool ?? false,
                isFork: object["fork"] as? Bool ?? false,
                language: object["language"] as? String,
                starCount: object["stargazers_count"] as? Int ?? 0,
                updatedAt: (object["updated_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            )
        }
    }

    private static func decodeOrgs(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array
    }

    private static func unavailable(_ message: String) -> GitHubStatusSnapshot {
        GitHubStatusSnapshot(
            isConnected: false,
            message: message,
            username: nil,
            accountCreatedAt: nil,
            publicRepoCount: nil,
            privateRepoCount: nil,
            forkCount: nil,
            organizations: [],
            recentRepositories: [],
            sampledAt: .now
        )
    }
}
