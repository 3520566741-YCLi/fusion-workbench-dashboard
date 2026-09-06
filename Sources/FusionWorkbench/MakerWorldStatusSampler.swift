import Foundation

struct MakerWorldModelInfo: Equatable, Identifiable, Sendable {
    var id: Int { designID }
    let designID: Int
    let title: String
    let slug: String
    let likeCount: Int
    let downloadCount: Int
    let printCount: Int
    let commentCount: Int
    let collectionCount: Int
    let updatedAt: Date?
}

struct MakerWorldStatusSnapshot: Equatable, Sendable {
    let isConnected: Bool
    let message: String
    let handle: String?
    let displayName: String?
    let avatarURL: String?
    let fanCount: Int?
    let followCount: Int?
    let likeCount: Int?
    let collectionCount: Int?
    let designCount: Int?
    let designDownloadCount: Int?
    let designPrintCount: Int?
    let models: [MakerWorldModelInfo]
    let sampledAt: Date

    static let unavailable = MakerWorldStatusSnapshot(
        isConnected: false,
        message: "Connecting to MakerWorld…",
        handle: nil,
        displayName: nil,
        avatarURL: nil,
        fanCount: nil,
        followCount: nil,
        likeCount: nil,
        collectionCount: nil,
        designCount: nil,
        designDownloadCount: nil,
        designPrintCount: nil,
        models: [],
        sampledAt: .now
    )
}

struct MakerWorldStatusSampler: Sendable {
    private static let baseURL = "https://api.bambulab.com/v1"
    // Profile id is intentionally blank in the public build. Set it to your own
    // MakerWorld id (e.g. defaults write com.fusionworkbench.dashboard makerWorldUserID -int 123456)
    // or edit the value below.
    private static let userID: Int = UserDefaults.standard.integer(forKey: "makerWorldUserID")

    func sample() async -> MakerWorldStatusSnapshot {
        await Task.detached(priority: .utility) { Self.readSnapshot() }.value
    }

    private static func readSnapshot() -> MakerWorldStatusSnapshot {
        guard userID > 0 else { return unavailable("MakerWorld user id is not set — configure makerWorldUserID (see README) to enable this card") }
        guard let profile = fetchJSON(path: "/design-user-service/user/profile/\(userID)") else {
            return unavailable("MakerWorld service is temporarily unavailable")
        }

        let models = profile["personal"] as? [String: Any] ?? [:]
        let designsInfo = models["designsInfo"] as? [[String: Any]] ?? []
        let knownIDs = designsInfo.compactMap { $0["id"] as? Int }

        // 从 MWCount 读取总数，若 designsInfo 未包含全部设计，按已知 id 补齐。
        let mwCount = profile["MWCount"] as? [String: Any] ?? [:]
        let designCount = mwCount["designCount"] as? Int
        let allIDs = knownIDs

        let modelList: [MakerWorldModelInfo] = allIDs.map { designID in
            fetchDesign(designID)
        }.compactMap { $0 }

        return MakerWorldStatusSnapshot(
            isConnected: true,
            message: "MakerWorld connected.",
            handle: profile["handle"] as? String,
            displayName: profile["name"] as? String,
            avatarURL: profile["avatar"] as? String,
            fanCount: profile["fanCount"] as? Int,
            followCount: profile["followCount"] as? Int,
            likeCount: profile["likeCount"] as? Int,
            collectionCount: profile["collectionCount"] as? Int,
            designCount: designCount,
            designDownloadCount: mwCount["myDesignDownloadCount"] as? Int,
            designPrintCount: mwCount["myDesignPrintCount"] as? Int,
            models: modelList,
            sampledAt: .now
        )
    }

    private static func fetchDesign(_ designID: Int) -> MakerWorldModelInfo? {
        guard let object = fetchJSON(path: "/design-service/design/\(designID)?trafficSource=browse") else { return nil }
        return MakerWorldModelInfo(
            designID: designID,
            title: object["title"] as? String ?? "Untitled model",
            slug: object["slug"] as? String ?? "",
            likeCount: object["likeCount"] as? Int ?? 0,
            downloadCount: object["downloadCount"] as? Int ?? 0,
            printCount: object["printCount"] as? Int ?? 0,
            commentCount: object["commentCount"] as? Int ?? 0,
            collectionCount: object["collectionCount"] as? Int ?? 0,
            updatedAt: (object["updateTime"] as? Int).map { Date(timeIntervalSince1970: Double($0)) }
        )
    }

    private static func fetchJSON(path: String) -> [String: Any]? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        let box = SendableBox<[String: Any]>()
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                box.value = object
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        return box.value
    }

    private final class SendableBox<T>: @unchecked Sendable {
        var value: T?
        init() { value = nil }
    }

    private static func unavailable(_ message: String) -> MakerWorldStatusSnapshot {
        MakerWorldStatusSnapshot(
            isConnected: false,
            message: message,
            handle: nil,
            displayName: nil,
            avatarURL: nil,
            fanCount: nil,
            followCount: nil,
            likeCount: nil,
            collectionCount: nil,
            designCount: nil,
            designDownloadCount: nil,
            designPrintCount: nil,
            models: [],
            sampledAt: .now
        )
    }
}
