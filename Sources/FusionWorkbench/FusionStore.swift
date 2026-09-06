import Foundation
import SwiftUI

@MainActor
final class FusionStore: ObservableObject {
    @Published var workspaces = Workspace.samples
    @Published var selectedWorkspaceID: UUID
    @Published var showsWeather = false
    @Published private(set) var dashboardLayout: [DashboardLayoutItem]
    @Published var isEditingLayout = false
    @Published var isComponentLibraryExpanded = false
    @Published private(set) var dashboardZoom: Double
    @Published private(set) var dashboardOffset: CGSize
    @Published private(set) var metrics = SystemMetrics.unavailable
    @Published private(set) var isMonitoring = false
    @Published private(set) var codexStatus = CodexStatusSnapshot.unavailable
    @Published private(set) var commandCodeStatus = CommandCodeStatusSnapshot.unavailable
    @Published private(set) var githubStatus = GitHubStatusSnapshot.unavailable
    @Published private(set) var makerWorldStatus = MakerWorldStatusSnapshot.unavailable
    @Published private(set) var harnessStatus = HarnessStatusSnapshot.unavailable

    private var sampler = SystemMetricsSampler()
    private var timer: Timer?
    private var isRefreshingCodexStatus = false
    private var lastCodexRefresh = Date.distantPast
    private var isRefreshingCommandCodeStatus = false
    private var lastCommandCodeRefresh = Date.distantPast
    private var isRefreshingGitHubStatus = false
    private var lastGitHubRefresh = Date.distantPast
    private var isRefreshingMakerWorldStatus = false
    private var lastMakerWorldRefresh = Date.distantPast
    private var isRefreshingHarnessStatus = false
    private var lastHarnessRefresh = Date.distantPast
    private let layoutKey = "fusion.dashboard.layout.v5"
    private let libraryKey = "fusion.dashboard.library-expanded.v1"
    private let zoomKey = "fusion.dashboard.zoom.v6"
    private let offsetXKey = "fusion.dashboard.offset.x.v5"
    private let offsetYKey = "fusion.dashboard.offset.y.v5"
    private let viewportConfiguredKey = "fusion.dashboard.viewport.configured.v5"

    init() {
        selectedWorkspaceID = Workspace.samples[0].id
        dashboardLayout = Self.loadLayout()
        if let savedZoom = UserDefaults.standard.object(forKey: "fusion.dashboard.zoom.v6") as? Double {
            dashboardZoom = min(2, max(0, savedZoom))
        } else {
            dashboardZoom = 1.0
        }
        dashboardOffset = CGSize(
            width: UserDefaults.standard.double(forKey: "fusion.dashboard.offset.x.v5"),
            height: UserDefaults.standard.double(forKey: "fusion.dashboard.offset.y.v5")
        )
        isComponentLibraryExpanded = UserDefaults.standard.bool(forKey: "fusion.dashboard.library-expanded.v1")
    }

    var selectedWorkspace: Workspace {
        workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces[0]
    }

    func startMonitoring() {
        guard timer == nil else { return }
        refreshMetrics()
        refreshCodexStatus()
        refreshCommandCodeStatus()
        refreshGitHubStatus()
        refreshMakerWorldStatus()
        refreshHarnessStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMetrics()
                self?.refreshCodexStatusIfNeeded()
                self?.refreshCommandCodeStatusIfNeeded()
                self?.refreshGitHubStatusIfNeeded()
                self?.refreshMakerWorldStatusIfNeeded()
                self?.refreshHarnessStatusIfNeeded()
            }
        }
        isMonitoring = true
    }

    func refreshMetrics() {
        metrics = sampler.sample()
    }

    func refreshCodexStatusIfNeeded() {
        guard Date.now.timeIntervalSince(lastCodexRefresh) >= 5 else { return }
        refreshCodexStatus()
    }

    func refreshCodexStatus() {
        guard !isRefreshingCodexStatus else { return }
        isRefreshingCodexStatus = true
        Task {
            let snapshot = await CodexStatusSampler().sample()
            codexStatus = snapshot
            lastCodexRefresh = .now
            isRefreshingCodexStatus = false
        }
    }

    func refreshCommandCodeStatusIfNeeded() {
        guard Date.now.timeIntervalSince(lastCommandCodeRefresh) >= 15 else { return }
        refreshCommandCodeStatus()
    }

    func refreshCommandCodeStatus() {
        guard !isRefreshingCommandCodeStatus else { return }
        isRefreshingCommandCodeStatus = true
        Task {
            let snapshot = await CommandCodeStatusSampler().sample()
            commandCodeStatus = snapshot
            lastCommandCodeRefresh = .now
            isRefreshingCommandCodeStatus = false
        }
    }

    func refreshGitHubStatusIfNeeded() {
        guard Date.now.timeIntervalSince(lastGitHubRefresh) >= 30 else { return }
        refreshGitHubStatus()
    }

    func refreshGitHubStatus() {
        guard !isRefreshingGitHubStatus else { return }
        isRefreshingGitHubStatus = true
        Task {
            let snapshot = await GitHubStatusSampler().sample()
            githubStatus = snapshot
            lastGitHubRefresh = .now
            isRefreshingGitHubStatus = false
        }
    }

    func refreshMakerWorldStatusIfNeeded() {
        guard Date.now.timeIntervalSince(lastMakerWorldRefresh) >= 60 else { return }
        refreshMakerWorldStatus()
    }

    func refreshMakerWorldStatus() {
        guard !isRefreshingMakerWorldStatus else { return }
        isRefreshingMakerWorldStatus = true
        Task {
            let snapshot = await MakerWorldStatusSampler().sample()
            makerWorldStatus = snapshot
            lastMakerWorldRefresh = .now
            isRefreshingMakerWorldStatus = false
        }
    }

    /// Harness 采样只读几个小 JSON 与进程列表，开销很低：跟随 2 秒监控心跳，
    /// 每次心跳都刷新，保证卡片上的运行状态 / 成本 / 会话及时更新。
    func refreshHarnessStatusIfNeeded() {
        guard Date.now.timeIntervalSince(lastHarnessRefresh) >= 2 else { return }
        refreshHarnessStatus()
    }

    func refreshHarnessStatus() {
        guard !isRefreshingHarnessStatus else { return }
        isRefreshingHarnessStatus = true
        Task {
            let snapshot = await HarnessStatusSampler().sample()
            harnessStatus = snapshot
            lastHarnessRefresh = .now
            isRefreshingHarnessStatus = false
        }
    }

    func showWorkspace(_ id: UUID) {
        selectedWorkspaceID = id
        showsWeather = false
    }

    func item(for id: DashboardModuleID) -> DashboardLayoutItem {
        dashboardLayout.first(where: { $0.id == id }) ?? DashboardLayoutItem.defaults.first(where: { $0.id == id })!
    }

    func setLibraryExpanded(_ expanded: Bool) {
        isComponentLibraryExpanded = expanded
        UserDefaults.standard.set(expanded, forKey: libraryKey)
    }

    func setVisibility(_ id: DashboardModuleID, visible: Bool) {
        update(id) { $0.isVisible = visible }
    }

    func setDashboardZoom(_ zoom: Double) {
        dashboardZoom = min(2, max(0, zoom))
        UserDefaults.standard.set(dashboardZoom, forKey: zoomKey)
        UserDefaults.standard.set(true, forKey: viewportConfiguredKey)
    }

    func setDashboardOffset(_ offset: CGSize) {
        dashboardOffset = offset
        UserDefaults.standard.set(offset.width, forKey: offsetXKey)
        UserDefaults.standard.set(offset.height, forKey: offsetYKey)
        UserDefaults.standard.set(true, forKey: viewportConfiguredKey)
    }

    var hasSavedViewport: Bool {
        UserDefaults.standard.bool(forKey: viewportConfiguredKey)
    }

    var visibleModuleCount: Int {
        dashboardLayout.filter(\.isVisible).count
    }

    func fitAll(in viewport: CGSize) {
        let items = dashboardLayout.filter(\.isVisible)
        guard let minX = items.map(\.x).min(), let minY = items.map(\.y).min(),
              let maxX = items.map({ $0.x + $0.width }).max(), let maxY = items.map({ $0.y + $0.height }).max() else {
            setDashboardZoom(1)
            setDashboardOffset(.zero)
            return
        }
        let cardGap: CGFloat = 4
        let cardPadding: CGFloat = 12
        let minPixelX = cardPadding + CGFloat(minX) * (DashboardCanvasLimits.cellWidth + cardGap)
        let minPixelY = cardPadding + CGFloat(minY) * (DashboardCanvasLimits.rowHeight + cardGap)
        let maxPixelX = cardPadding + CGFloat(maxX) * (DashboardCanvasLimits.cellWidth + cardGap) - cardGap
        let maxPixelY = cardPadding + CGFloat(maxY) * (DashboardCanvasLimits.rowHeight + cardGap) - cardGap
        let contentWidth = maxPixelX - minPixelX
        let contentHeight = maxPixelY - minPixelY
        let margin = min(28, max(12, min(viewport.width, viewport.height) * 0.02))
        let availableWidth = max(1, viewport.width - margin * 2)
        let availableHeight = max(1, viewport.height - margin * 2)
        let scale = min(2, max(0.05, min(availableWidth / max(1, contentWidth), availableHeight / max(1, contentHeight))))
        let offset = CGSize(
            width: margin + (availableWidth - contentWidth * scale) / 2 - minPixelX * scale,
            height: margin + (availableHeight - contentHeight * scale) / 2 - minPixelY * scale
        )
        setDashboardZoom(scale)
        setDashboardOffset(offset)
    }

    /// “自适应摆放”：把可视模块切分成若干整宽行并扫描“行宽列数”，
    /// 让整组内容的外接框宽高比贴合当前窗口（四周只留“适应全部”式小边距），
    /// 行内每张卡宽度按设计比例分配，行高反推尽量贴近设计比例，减小卡内留白。
    func autoArrange(in viewport: CGSize) {
        let visible = dashboardLayout.filter(\.isVisible)
        guard !visible.isEmpty, viewport.width > 0, viewport.height > 0 else { return }

        let margin = min(28, max(12, min(viewport.width, viewport.height) * 0.02))
        let usableWidth = max(1, viewport.width - margin * 2)
        let usableHeight = max(1, viewport.height - margin * 2)
        let slotWidth: CGFloat = 100  // 96 宽 + 4 间隙
        let slotHeight: CGFloat = 112 // 108 高 + 4 间隙
        let viewportAspect = Double(usableWidth) / Double(usableHeight)
        let widthFitColumns = max(4, Int((usableWidth / slotWidth).rounded()))
        // 列数扫描范围：允许比“一屏宽”更宽，最终由 fitAll 缩放贴合整个窗口。
        let maxColumns = min(48, max(14, widthFitColumns * 3))

        // 按组件列表顺序作为摆放顺序（自适应布局会先按当前画布位置重排数组再调用这里）。
        let items = visible
        let count = items.count

        var best: (columns: Int, rows: [AutoRow])?
        var bestScore = Double.infinity
        for columns in 6...max(6, maxColumns) {
            // 枚举所有“在相邻模块之间切行”的方案（模块数很少，2^(n-1) 种足够快）。
            for mask in 0..<(1 << max(0, count - 1)) {
                var rows: [AutoRow] = []
                var start = 0
                var feasible = true
                for bit in 0..<max(0, count - 1) {
                    if mask & (1 << bit) != 0 {
                        let end = bit + 1
                        guard let row = autoRow(range: start..<end, items: items, columns: columns) else {
                            feasible = false
                            break
                        }
                        rows.append(row)
                        start = end
                    }
                }
                guard feasible, start < count, let tail = autoRow(range: start..<count, items: items, columns: columns) else { continue }
                rows.append(tail)

                let totalCells = rows.reduce(0) { $0 + $1.height }
                guard totalCells >= 1, totalCells <= 90 else { continue }
                let contentAspect = Double(columns) * Double(slotWidth) / (Double(totalCells) * Double(slotHeight))
                // 主目标：内容框宽高比贴合窗口（铺满）；辅以最小尺寸与比例漂移惩罚。
                var score = 700 * abs(log(contentAspect / viewportAspect))
                score += Double(rows.count) * 2
                for row in rows {
                    let slice = Array(items[row.range])
                    for index in slice.indices {
                        let design = slice[index].id.designSize
                        let widthRatio = CGFloat(row.widths[index]) * slotWidth / (CGFloat(design.width) * slotWidth)
                        let heightRatio = CGFloat(row.height) * slotHeight / (CGFloat(design.height) * slotHeight)
                        let relative = min(widthRatio, heightRatio)
                        if relative < 0.55 { score += (0.55 - relative) * 180 }
                        score += 30 * abs(log(max(widthRatio, 0.001) / max(heightRatio, 0.001)))
                    }
                }
                if score < bestScore - 1e-9 {
                    bestScore = score
                    best = (columns, rows)
                }
            }
        }

        guard let rows = best?.rows else { return }
        var planned: [DashboardLayoutItem] = []
        var y = 0
        for row in rows {
            let slice = items[row.range]
            var x = 0
            for (index, item) in slice.enumerated() {
                var placed = item
                placed.x = x
                placed.y = y
                placed.width = row.widths[index]
                placed.height = row.height
                guard placed.x + placed.width <= DashboardCanvasLimits.columns,
                      placed.y + placed.height <= DashboardCanvasLimits.rows else { return }
                planned.append(placed)
                x += placed.width
            }
            y += row.height
        }
        guard planned.count == count else { return }

        var layout = dashboardLayout
        for planItem in planned {
            guard let index = layout.firstIndex(where: { $0.id == planItem.id && $0.isVisible }) else { continue }
            layout[index] = planItem
        }
        dashboardLayout = layout
        persistLayout()
        fitAll(in: viewport)
    }

    /// “自适应布局”：依据用户当前的摆放（先上后下、再左后右的相对顺序），
    /// 把整组模块按该顺序重新铺满当前窗口——位置布局不变只是空隙重排成满窗马赛克。
    func autoFitLayout(in viewport: CGSize) {
        let visible = dashboardLayout.filter(\.isVisible)
        guard !visible.isEmpty else { return }
        // 先把数组排成与当前画布一致（上→下、左→右）的顺序，再做满窗排列。
        let sorted = visible.sorted { ($0.y, $0.x, $0.id.rawValue) < ($1.y, $1.x, $1.id.rawValue) }
        let hidden = dashboardLayout.filter { !$0.isVisible }
        dashboardLayout = sorted + hidden
        autoArrange(in: viewport)
    }

    private struct AutoRow {
        let range: Range<Int>
        let height: Int
        let widths: [Int]
    }

    /// 计算某一行（items[range]）的排布：行内模块宽度按各自设计宽高比成比例铺满整行。
    private func autoRow(range: Range<Int>, items: [DashboardLayoutItem], columns: Int) -> AutoRow? {
        let slice = Array(items[range])
        guard !slice.isEmpty else { return nil }
        guard slice.reduce(0, { $0 + $1.id.minimumSize.width }) <= columns else { return nil }

        let slotWidth: CGFloat = 100
        let slotHeight: CGFloat = 112
        var aspectSum: CGFloat = 0
        var aspects: [CGFloat] = []
        for item in slice {
            let design = item.id.designSize
            let aspect = CGFloat(design.width) * slotWidth / (CGFloat(design.height) * slotHeight)
            aspects.append(aspect)
            aspectSum += aspect
        }
        // 整行宽列数对应的像素宽 / 比例和 = 该行想要达到的像素高。
        let rowPixelHeight = (CGFloat(columns) * slotWidth) / aspectSum
        // 行高取“比例高度”与该行模块最小高度的较大者：允许高卡片所在行略高于纯比例需求
        // （轻微拉伸由卡内弹性排版消化），避免高卡片把可行排布卡死成竖条。
        let roundedHeight = max(1, Int((rowPixelHeight / slotHeight).rounded()))
        let cellsHeight = max(roundedHeight, slice.map { $0.id.minimumSize.height }.max() ?? 1)

        // 宽列数按各自比例分配（保持比例尽量接近设计宽高比）。
        let widthWeights = slice.indices.map { aspects[$0] * rowPixelHeight / slotWidth }
        let minimumWidths = slice.map { $0.id.minimumSize.width }
        let widths = Self.fillWidths(minimums: minimumWidths, weights: widthWeights, target: columns)
        return AutoRow(range: range, height: cellsHeight, widths: widths)
    }

    /// 把 target 个格子按 weights 比例分配到各项，且每项不低于 minimums。
    private static func fillWidths(minimums: [Int], weights: [CGFloat], target: Int) -> [Int] {
        guard minimums.count == weights.count, !minimums.isEmpty else { return [] }
        let reserved = minimums.reduce(0, +)
        let extra = max(0, target - reserved)
        var result = minimums
        guard extra > 0 else { return result }
        let weightSum = max(1, weights.reduce(0, +))
        // floor + 最大余数法：既保证总量精确，又尽量贴近比例。
        let floats = weights.map { Double(extra) * Double($0) / Double(weightSum) }
        var allocation = floats.map { Int($0.rounded(.down)) }
        var deficit = extra - allocation.reduce(0, +)
        if deficit > 0 {
            let order = floats.indices.sorted { floats[$0] - Double(allocation[$0]) > floats[$1] - Double(allocation[$1]) }
            for index in order where deficit > 0 {
                allocation[index] += 1
                deficit -= 1
            }
        }
        for index in result.indices {
            result[index] += allocation[index]
        }
        return result
    }

    func move(_ id: DashboardModuleID, toX x: Int, y: Int, columns: Int) {
        guard var candidate = dashboardLayout.first(where: { $0.id == id }) else { return }
        candidate.width = min(candidate.width, columns)
        candidate.x = max(0, min(columns - candidate.width, x))
        candidate.y = max(0, y)
        guard isValid(candidate, excluding: id, columns: columns) else { return }
        replace(candidate)
        persistLayout()
    }

    func resize(_ id: DashboardModuleID, width: Int, height: Int, columns: Int) {
        guard var candidate = dashboardLayout.first(where: { $0.id == id }) else { return }
        let minimum = id.minimumSize
        candidate.width = max(minimum.width, min(columns - candidate.x, width))
        candidate.height = max(minimum.height, height)
        guard isValid(candidate, excluding: id, columns: columns) else { return }
        replace(candidate)
        persistLayout()
    }

    func isValid(_ item: DashboardLayoutItem, excluding id: DashboardModuleID, columns: Int) -> Bool {
        guard item.x >= 0, item.y >= 0, item.width > 0, item.height > 0,
              item.x + item.width <= columns,
              item.y + item.height <= DashboardCanvasLimits.rows else { return false }
        return !dashboardLayout.contains { $0.id != id && $0.isVisible && overlaps(item, $0) }
    }

    func resetDashboardLayout(columns: Int = DashboardCanvasLimits.columns) {
        dashboardLayout = DashboardLayoutItem.defaults
        persistLayout()
        // 连缩放与平移一起归位，并清除“已手动调整过视口”标记，让画布回到初始满屏布局。
        setDashboardZoom(1)
        setDashboardOffset(.zero)
        UserDefaults.standard.removeObject(forKey: viewportConfiguredKey)
    }

    private func update(_ id: DashboardModuleID, mutation: (inout DashboardLayoutItem) -> Void) {
        guard let index = dashboardLayout.firstIndex(where: { $0.id == id }) else { return }
        mutation(&dashboardLayout[index])
        persistLayout()
    }

    private func replace(_ item: DashboardLayoutItem) {
        guard let index = dashboardLayout.firstIndex(where: { $0.id == item.id }) else { return }
        dashboardLayout[index] = item
    }

    private func compactLayout(preserving id: DashboardModuleID, columns: Int) {
        let safeColumns = max(1, columns)
        guard let preservedIndex = dashboardLayout.firstIndex(where: { $0.id == id }) else { return }
        dashboardLayout[preservedIndex].width = min(dashboardLayout[preservedIndex].width, safeColumns)
        dashboardLayout[preservedIndex].x = min(dashboardLayout[preservedIndex].x, safeColumns - dashboardLayout[preservedIndex].width)

        let ordered = dashboardLayout.indices
            .filter { dashboardLayout[$0].id != id && dashboardLayout[$0].isVisible }
            .sorted {
                let left = dashboardLayout[$0]
                let right = dashboardLayout[$1]
                return (left.y, left.x, left.id.rawValue) < (right.y, right.x, right.id.rawValue)
            }
        var occupied = [dashboardLayout[preservedIndex]]

        for index in ordered {
            var item = dashboardLayout[index]
            item.width = min(item.width, safeColumns)
            if let position = firstAvailablePosition(for: item, occupied: occupied, columns: safeColumns) {
                item.x = position.x
                item.y = position.y
            }
            dashboardLayout[index] = item
            occupied.append(item)
        }
    }

    private func firstAvailablePosition(for item: DashboardLayoutItem, occupied: [DashboardLayoutItem], columns: Int) -> (x: Int, y: Int)? {
        for y in 0...80 {
            for x in 0...(columns - item.width) {
                var candidate = item
                candidate.x = x
                candidate.y = y
                if !occupied.contains(where: { overlaps(candidate, $0) }) { return (x, y) }
            }
        }
        return nil
    }

    private func overlaps(_ left: DashboardLayoutItem, _ right: DashboardLayoutItem) -> Bool {
        left.x < right.x + right.width && left.x + left.width > right.x &&
        left.y < right.y + right.height && left.y + left.height > right.y
    }

    private func persistLayout() {
        if let data = try? JSONEncoder().encode(dashboardLayout) {
            UserDefaults.standard.set(data, forKey: layoutKey)
        }
    }

    private static func loadLayout() -> [DashboardLayoutItem] {
        var layout: [DashboardLayoutItem]
        if let data = UserDefaults.standard.data(forKey: "fusion.dashboard.layout.v5"),
           let saved = try? JSONDecoder().decode([DashboardLayoutItem].self, from: data) {
            layout = saved
        } else {
            layout = []
        }
        // 升级旧布局：补上缺失的新模块，保留用户已保存的布局。
        for item in DashboardLayoutItem.defaults where !layout.contains(where: { $0.id == item.id }) {
            layout.append(item)
        }
        guard layout.allSatisfy({ $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.height > 0 && $0.x + $0.width <= 12 }) else {
            return DashboardLayoutItem.defaults
        }
        return layout
    }
}
