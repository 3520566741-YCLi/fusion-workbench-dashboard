import SwiftUI
import WebKit

private let gridGap: CGFloat = 4
private let gridPadding: CGFloat = 12

struct FusionDashboard: View {
    @EnvironmentObject private var store: FusionStore
    @AppStorage(AppLanguage.defaultsKey) private var language = "en"

    var body: some View {
        HStack(spacing: 0) {
            ComponentLibrary()
            Divider()
            DashboardCanvas()
        }
        .id(language)
        .task { store.startMonitoring() }
    }
}

private struct ComponentLibrary: View {
    @EnvironmentObject private var store: FusionStore

    var body: some View {
        VStack(alignment: store.isComponentLibraryExpanded ? .leading : .center, spacing: 16) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)
                if store.isComponentLibraryExpanded {
                    Text(tr("Component Library")).font(.title3.bold())
                }
                Spacer(minLength: 0)
                Button(action: { store.setLibraryExpanded(!store.isComponentLibraryExpanded) }) {
                    Image(systemName: store.isComponentLibraryExpanded ? "chevron.left" : "chevron.right")
                }
                .buttonStyle(.borderless)
                .help(store.isComponentLibraryExpanded ? tr("Collapse Library") : tr("Expand Library"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            if store.isComponentLibraryExpanded {
                Text(tr("Show or Hide Canvas Modules · {n} / {m}", store.visibleModuleCount, DashboardCanvasLimits.maximumVisibleModules))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)

                ForEach(DashboardModuleID.allCases) { module in
                    Toggle(isOn: Binding(
                        get: { store.item(for: module).isVisible },
                        set: { store.setVisibility(module, visible: $0) }
                    )) {
                        Label(module.title, systemImage: module.symbol)
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 14)
                }

                Divider().padding(.horizontal, 14)
                Button(tr("Reset Default Layout")) { store.resetDashboardLayout() }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 14)
            } else {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(tr("Modules"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer()
        }
        .frame(width: store.isComponentLibraryExpanded ? 240 : 68)
        .animation(.snappy, value: store.isComponentLibraryExpanded)
        .background(.thinMaterial)
    }
}

private struct DashboardCanvas: View {
    @EnvironmentObject private var store: FusionStore
    @AppStorage(AppLanguage.defaultsKey) private var language = "en"

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar keeps the original look and controls: zoom − / slider / percent / zoom + / edit layout.
            HStack(spacing: 10) {
                Picker("Language", selection: $language) {
                    Text("EN").tag("en")
                    Text("中文").tag("zh")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 110)
                .help(tr("Switch between English and Chinese"))
                Spacer()
                Button { store.setDashboardZoom(store.dashboardZoom - 0.1) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Slider(value: Binding(get: { store.dashboardZoom }, set: { store.setDashboardZoom($0) }), in: 0...2)
                    .frame(width: 120)
                Text(store.dashboardZoom.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit()).frame(width: 42)
                Button { store.setDashboardZoom(store.dashboardZoom + 0.1) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button(store.isEditingLayout ? tr("Finish Layout") : tr("Edit Layout")) {
                    store.isEditingLayout.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .frame(height: 40)
            Divider()

            GeometryReader { proxy in
                VirtualCanvasViewport(viewport: proxy.size)
            }
        }
    }
}

private struct DashboardGrid: Equatable {
    let columns = DashboardCanvasLimits.columns
    let cellWidth = DashboardCanvasLimits.cellWidth
    let rowHeight = DashboardCanvasLimits.rowHeight

    func width(for item: DashboardLayoutItem) -> CGFloat {
        CGFloat(item.width) * cellWidth + CGFloat(item.width - 1) * gridGap
    }

    func height(for item: DashboardLayoutItem) -> CGFloat {
        CGFloat(item.height) * rowHeight + CGFloat(item.height - 1) * gridGap
    }

    func centerX(for item: DashboardLayoutItem) -> CGFloat {
        gridPadding + CGFloat(item.x) * (cellWidth + gridGap) + width(for: item) / 2
    }

    func centerY(for item: DashboardLayoutItem) -> CGFloat {
        gridPadding + CGFloat(item.y) * (rowHeight + gridGap) + height(for: item) / 2
    }

    func columnDelta(for offset: CGFloat) -> Int {
        Int((offset / (cellWidth + gridGap)).rounded())
    }

    func rowDelta(for offset: CGFloat) -> Int {
        Int((offset / (rowHeight + gridGap)).rounded())
    }

    func clamped(_ item: DashboardLayoutItem) -> DashboardLayoutItem {
        var result = item
        result.width = min(result.width, columns)
        result.x = max(0, min(result.x, columns - result.width))
        result.y = max(0, result.y)
        return result
    }
}

private struct VirtualCanvasViewport: View {
    @EnvironmentObject private var store: FusionStore
    let viewport: CGSize
    @State private var isSpaceHeld = false
    @State private var panStart: CGSize?
    @State private var magnifyStart = 1.0
    @State private var didInitialFit = false

    var body: some View {
        let grid = DashboardGrid()
        GridSurface(grid: grid)
            .frame(width: CGFloat(DashboardCanvasLimits.columns) * grid.cellWidth, height: CGFloat(DashboardCanvasLimits.rows) * grid.rowHeight)
            .scaleEffect(store.dashboardZoom, anchor: .topLeading)
            .offset(store.dashboardOffset)
            .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(panGesture)
            .focusable()
            .onKeyPress(.space, phases: [.down, .up]) { press in
                isSpaceHeld = press.phase == .down
                if !isSpaceHeld { panStart = nil }
                return .handled
            }
            .task(id: viewport) {
                guard viewport.width > 0, viewport.height > 0 else { return }
                try? await Task.sleep(for: .milliseconds(150))
                store.fitAll(in: viewport)
            }
            .overlay(alignment: .bottomTrailing) {
                // 布局按钮组：以液态玻璃胶囊悬浮在画布右下角，彼此靠近时会融合成一体。
                // 右下角悬浮按钮组：保留原先带边框的按钮样式与功能，不做改动。
                HStack(spacing: 8) {
                    Button {
                        store.autoFitLayout(in: viewport)
                    } label: {
                        Label(tr("Auto Layout"), systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                    .help(tr("Rearranges cards into full rows following your current reading order (top → bottom, left → right) and fills the whole window."))
                    Button {
                        store.autoArrange(in: viewport)
                    } label: {
                        Label(tr("Auto Arrange"), systemImage: "square.grid.3x3.fill")
                    }
                    .buttonStyle(.bordered)
                    .help(tr("Rearranges and resizes cards by their aspect ratio to fill the current view."))
                    Button(tr("Fit All")) { store.fitAll(in: viewport) }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .help(tr("Only zooms and pans; keeps the current arrangement."))
                }
                .padding(16)
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyStart == 1 { magnifyStart = store.dashboardZoom }
                store.setDashboardZoom(magnifyStart * value.magnification)
            }
            .onEnded { _ in magnifyStart = 1 }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isSpaceHeld else { return }
                if panStart == nil { panStart = store.dashboardOffset }
                let start = panStart ?? .zero
                store.setDashboardOffset(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height))
            }
            .onEnded { _ in panStart = nil }
    }
}

private struct GridSurface: View {
    @EnvironmentObject private var store: FusionStore
    let grid: DashboardGrid
    @State private var preview: DashboardLayoutPreview?

    private var visibleItems: [DashboardLayoutItem] {
        store.dashboardLayout.filter(\.isVisible).map(grid.clamped)
    }

    private var canvasHeight: CGFloat {
        let rows = max(5, (visibleItems.map { $0.y + $0.height }.max() ?? 0) + 1)
        return gridPadding * 2 + CGFloat(rows) * grid.rowHeight + CGFloat(rows - 1) * gridGap
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.isEditingLayout { CanvasGrid(grid: grid) }
            ForEach(visibleItems) { item in
                DashboardModuleCard(item: item, renderedItem: item, grid: grid, preview: $preview)
                    .frame(width: grid.width(for: item), height: grid.height(for: item))
                    .clipped()
                    .position(x: grid.centerX(for: item), y: grid.centerY(for: item))
                    // 拖动/缩放过程中被操作的卡片保持原位并半透明，
                    // 目标位置由虚线框表达：避免“卡片移动→手势坐标跟着移动”的反馈抖动。
                    .opacity(preview?.id == item.id ? 0.35 : 1)
                    .animation(.snappy(duration: 0.12), value: preview?.id)
            }
            if let preview {
                DragPreviewOverlay(preview: preview, grid: grid)
            }
        }
        .frame(width: CGFloat(DashboardCanvasLimits.columns) * grid.cellWidth, height: CGFloat(DashboardCanvasLimits.rows) * grid.rowHeight, alignment: .topLeading)
    }
}

private struct DragPreviewOverlay: View {
    let preview: DashboardLayoutPreview
    let grid: DashboardGrid

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(preview.isValid ? Color.mint : Color.orange, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            }
            .frame(width: grid.width(for: preview.item), height: grid.height(for: preview.item))
            .position(x: grid.centerX(for: preview.item), y: grid.centerY(for: preview.item))
            .allowsHitTesting(false)
    }
}

private struct CanvasGrid: View {
    let grid: DashboardGrid

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for column in 0...grid.columns {
                    let x = gridPadding + CGFloat(column) * (grid.cellWidth + gridGap)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
                for row in stride(from: gridPadding, through: proxy.size.height, by: grid.rowHeight + gridGap) {
                    path.move(to: CGPoint(x: 0, y: row))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: row))
                }
            }
            .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
        }
        .opacity(0.32)
        .allowsHitTesting(false)
    }
}

private struct DashboardModuleCard: View {
    @EnvironmentObject private var store: FusionStore
    let item: DashboardLayoutItem
    let renderedItem: DashboardLayoutItem
    let grid: DashboardGrid
    @Binding var preview: DashboardLayoutPreview?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 所有模块一律「整卡活排版」：模块内容用各自的 GeometryReader 弹性排布，
            // 字号随卡片等比缩放、弹性空隙把内容纵向撑满整张卡。
            // 不再有「先按设计尺寸排版、再整卡等比缩放」的死板方式；
            // 以后新增模块也按 LiveLayout.swift 里的约定排版，即自动获得同样的灵活性。
            ModuleContent(id: item.id)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // 每张数据卡是一块圆角液态玻璃，折射画布底色。
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

            if store.isEditingLayout {
                Rectangle()
                    .fill(.clear)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .gesture(dragGesture)
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption.bold())
                    .padding(8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(10)
                    .allowsHitTesting(false)

                // 底部中央手柄：上下拖动只改高度（可拉高也可压矮）。
                Image(systemName: "arrow.up.and.down")
                    .font(.caption.bold())
                    .padding(.vertical, 9)
                    .padding(.horizontal, 7)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
                    .gesture(resizeGesture(axes: .height))

                // 右侧中央手柄：左右拖动只改宽度。
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.bold())
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .gesture(resizeGesture(axes: .width))

                // 右下角手柄：同时改宽高。
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.caption.bold())
                    .padding(8)
                    .glassEffect(.regular, in: .circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                    .gesture(resizeGesture(axes: .both))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                var candidate = item
                candidate.x = max(0, min(grid.columns - candidate.width, item.x + grid.columnDelta(for: value.translation.width)))
                candidate.y = max(0, item.y + grid.rowDelta(for: value.translation.height))
                preview = DashboardLayoutPreview(id: item.id, item: candidate, isValid: store.isValid(candidate, excluding: item.id, columns: grid.columns), isResize: false)
            }
            .onEnded { _ in
                if let preview, preview.id == item.id, preview.isValid {
                    store.move(item.id, toX: preview.item.x, y: preview.item.y, columns: grid.columns)
                }
                preview = nil
            }
    }

    /// 缩放轴向：只有一侧变化，用户在拖动时不会被另一轴的微小偏移干扰。
    private enum ResizeAxis {
        case width, height, both
    }

    private func resizeGesture(axes: ResizeAxis) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var candidate = item
                let minimum = item.id.minimumSize
                if axes != .height {
                    candidate.width = max(minimum.width, min(grid.columns - candidate.x, item.width + grid.columnDelta(for: value.translation.width)))
                }
                if axes != .width {
                    candidate.height = max(minimum.height, item.height + grid.rowDelta(for: value.translation.height))
                }
                preview = DashboardLayoutPreview(id: item.id, item: candidate, isValid: store.isValid(candidate, excluding: item.id, columns: grid.columns), isResize: true)
            }
            .onEnded { _ in
                if let preview, preview.id == item.id, preview.isValid {
                    store.resize(item.id, width: preview.item.width, height: preview.item.height, columns: grid.columns)
                }
                preview = nil
            }
    }
}

private struct ModuleContent: View {
    @EnvironmentObject private var store: FusionStore
    let id: DashboardModuleID

    var body: some View {
        switch id {
        case .weather: WeatherModule()
        case .system: SystemModule()
        case .codex: CodexModule()
        case .commandCode: CommandCodeModule()
        case .github: GitHubModule()
        case .makerWorld: MakerWorldModule()
        case .harness: HarnessModule()
        }
    }
}

private struct WeatherModule: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(tr("Nullschool Earth Weather"), systemImage: "globe.americas.fill")
                    .font(.headline)
                Spacer()
                Text(tr("Live Wind and Weather Map"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            NullschoolWebView()
        }
    }
}

private struct NullschoolWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: URL(string: "https://earth.nullschool.net/")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}

private struct SystemModule: View {
    @EnvironmentObject private var store: FusionStore

    /// 设计基准：Mac 卡默认 4×6 格换算成像素；此尺寸下 f = 1。
    private static let designSize = LiveLayout.pixelDesign(columns: 4, rows: 6)

    var body: some View {
        GeometryReader { proxy in
            let f = LiveLayout.textFactor(for: proxy.size, design: Self.designSize)
            VStack(alignment: .leading, spacing: 0) {
                header(f)
                Spacer(minLength: 7 * f)
                Divider()
                if store.metrics.cpuPercent == nil && store.metrics.memoryUsedBytes == 0 {
                    Spacer(minLength: 5 * f)
                    Text(tr("Waiting for the First Sample…"))
                        .font(.system(size: 12 * f))
                        .foregroundStyle(.secondary)
                } else {
                    metricRows(f)
                }
                Spacer(minLength: 8 * f)
                Text(tr("Updated {s}", store.metrics.sampledAt.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10 * f))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func header(_ f: CGFloat) -> some View {
        HStack {
            Label(tr("Mac Status"), systemImage: "desktopcomputer")
                .font(.system(size: 15 * f, weight: .semibold))
            Spacer(minLength: 8)
            HStack(spacing: 5 * f) {
                Circle()
                    .fill(store.isMonitoring ? .mint : .gray)
                    .frame(width: 8 * f, height: 8 * f)
                Text(store.isMonitoring ? tr("Monitoring") : tr("Paused"))
                    .font(.system(size: 11 * f, weight: .semibold))
                    .foregroundStyle(store.isMonitoring ? .mint : .secondary)
            }
        }
    }

    @ViewBuilder
    private func metricRows(_ f: CGFloat) -> some View {
        metricRow(title: cpuTitle,
                  value: store.metrics.cpuPercent.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? tr("Sampling"),
                  progress: store.metrics.cpuPercent,
                  factor: f)
        Spacer(minLength: 6 * f)
        metricRow(title: tr("Memory"),
                  value: "\(ByteCountFormatter.string(fromByteCount: Int64(store.metrics.memoryUsedBytes), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(store.metrics.memoryTotalBytes), countStyle: .memory))",
                  progress: store.metrics.memoryPercent,
                  factor: f)
        Spacer(minLength: 6 * f)
        metricRow(title: tr("Disk"),
                  value: tr("Available {s}", ByteCountFormatter.string(fromByteCount: store.metrics.diskAvailableBytes, countStyle: .file)),
                  progress: store.metrics.diskPercent,
                  factor: f)
        if let gpu = store.metrics.gpu {
            Spacer(minLength: 6 * f)
            metricRow(title: gpu.coreCount.map { tr("GPU · {n} Cores", $0) } ?? tr(tr("GPU")),
                      value: gpu.deviceUtilization.map { tr("Device {s}", $0.formatted(.percent.precision(.fractionLength(0)))) } ?? tr("Unavailable"),
                      progress: gpu.deviceUtilization,
                      factor: f)
            Spacer(minLength: 6 * f)
            metricRow(title: "Renderer",
                      value: gpu.rendererUtilization.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? tr("Unavailable"),
                      progress: gpu.rendererUtilization,
                      factor: f)
            Spacer(minLength: 6 * f)
            metricRow(title: "Tiler",
                      value: gpu.tilerUtilization.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? tr("Unavailable"),
                      progress: gpu.tilerUtilization,
                      factor: f)
        }
    }

    private func metricRow(title: String, value: String, progress: Double?, factor f: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * f) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12 * f, weight: .medium))
                    .layoutPriority(1)
                Spacer(minLength: 6)
                Text(value)
                    .font(.system(size: 12 * f))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let progress {
                LiveLayout.usageBar(progress: progress, factor: f)
            }
        }
    }

    private var cpuTitle: String {
        if let performance = store.metrics.cpuPerformanceCores, let efficiency = store.metrics.cpuEfficiencyCores {
            return "CPU · \(performance)P + \(efficiency)E"
        }
        return "CPU"
    }
}

private struct CodexModule: View {
    @EnvironmentObject private var store: FusionStore

    private static let designSize = CGSize(width: 440, height: 336)

    var body: some View {
        GeometryReader { proxy in
            let f = Self.textFactor(for: proxy.size)
            let status = store.codexStatus
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(tr("Codex Status"), systemImage: "sparkles")
                        .font(.system(size: 15 * f, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(statusTitle)
                        .font(.system(size: 11 * f, weight: .semibold))
                        .foregroundStyle(statusTint)
                }
                if status.isConnected {
                    if !status.runningTasks.isEmpty {
                        Spacer(minLength: 4 * f)
                        ForEach(status.runningTasks.prefix(3)) { task in
                            taskRow(task: task, factor: f)
                            Spacer(minLength: 3 * f)
                        }
                    } else {
                        Spacer(minLength: 5 * f)
                    }
                    codexUsageRow(title: tr("Last 5 Hours"), window: status.fiveHourUsage, unavailableMessage: status.usageMessage, factor: f)
                    Spacer(minLength: 6 * f)
                    codexUsageRow(title: tr("This Week"), window: status.weeklyUsage, unavailableMessage: status.usageMessage, factor: f)
                } else {
                    Spacer(minLength: 5 * f)
                    Text(tr(status.message))
                        .font(.system(size: 12 * f))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private static func textFactor(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(2.0, max(0.45, min(size.width / designSize.width, size.height / designSize.height)))
    }

    private func taskRow(task: CodexTaskStatus, factor f: CGFloat) -> some View {
        HStack(spacing: 6 * f) {
            Image(systemName: task.needsAttention ? "exclamationmark.circle.fill" : "play.circle.fill")
                .font(.system(size: 11 * f))
                .foregroundStyle(task.needsAttention ? .orange : .mint)
            Text(task.title)
                .font(.system(size: 11 * f, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(task.needsAttention ? tr("Needs Your Confirmation") : tr("Running"))
                .font(.system(size: 10 * f, weight: .semibold))
                .foregroundStyle(task.needsAttention ? .orange : .secondary)
        }
    }

    private func codexUsageRow(title: String, window: CodexUsageWindow?, unavailableMessage: String?, factor f: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * f) {
            HStack {
                Text(title).font(.system(size: 12 * f))
                Spacer(minLength: 4)
                Text(window.map { tr("Remaining {n}%", $0.remainingPercent) } ?? unavailableMessage ?? tr("Reading"))
                    .font(.system(size: 12 * f, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let window {
                // Codex 用量条与 Mac 相反：条宽表示“剩余比例”，颜色表示“已用方向”——
                // 剩余越少越红、剩余充足越绿。
                LiveLayout.usageBar(progress: min(1, max(0, Double(window.remainingPercent) / 100)),
                                    colorUsage: Double(window.usedPercent) / 100,
                                    factor: f)
                Text(tr("Used {n}%", window.usedPercent))
                    .font(.system(size: 10 * f))
                    .foregroundStyle(.secondary)
                if let resetsAt = window.resetsAt {
                    Text(tr("Resets at {s}", resetsAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 10 * f))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusTitle: String {
        if !store.codexStatus.isConnected { return tr("Unavailable") }
        if store.codexStatus.runningTasks.contains(where: \.needsAttention) { return tr("Needs Your Confirmation") }
        return store.codexStatus.runningTasks.isEmpty ? tr("Connected") : tr("Running")
    }

    private var statusTint: Color {
        !store.codexStatus.isConnected ? .secondary : store.codexStatus.runningTasks.contains(where: \.needsAttention) ? .orange : .mint
    }
}

private struct CommandCodeModule: View {
    @EnvironmentObject private var store: FusionStore

    private static let designSize = CGSize(width: 440, height: 336)

    var body: some View {
        GeometryReader { proxy in
            let f = Self.textFactor(for: proxy.size)
            let status = store.commandCodeStatus
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(tr("Command Code Status"), systemImage: "terminal.fill")
                        .font(.system(size: 15 * f, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(statusTitle)
                        .font(.system(size: 11 * f, weight: .semibold))
                        .foregroundStyle(statusTint)
                }
                if status.isConnected {
                    Spacer(minLength: 8 * f)
                    infoRow(title: tr("Signed-in Account"), value: status.authenticatedUser ?? tr("Unavailable"), factor: f)
                    Spacer(minLength: 5 * f)
                    infoRow(title: tr("App Version"), value: status.version ?? tr("Unavailable"), factor: f)
                    Spacer(minLength: 6 * f)
                    Divider()
                    VStack(alignment: .leading, spacing: 3 * f) {
                        Text(tr("Usage & Subscription")).font(.system(size: 11 * f, weight: .semibold))
                        Text(tr("Command Code does not expose an automatic read API — check usage, remaining quota and subscription expiry inside Command Code with /usage."))
                            .font(.system(size: 10 * f))
                            .foregroundStyle(.secondary)
                            .lineSpacing(1.5 * f)
                    }
                } else {
                    Spacer(minLength: 5 * f)
                    Text(tr(status.message)).font(.system(size: 12 * f)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(tr("Updated {s}", status.sampledAt.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10 * f))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private static func textFactor(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(2.0, max(0.45, min(size.width / designSize.width, size.height / designSize.height)))
    }

    private func infoRow(title: String, value: String, factor f: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12 * f))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12 * f, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusTitle: String {
        store.commandCodeStatus.isConnected ? tr("Connected") : tr("Unavailable")
    }

    private var statusTint: Color {
        store.commandCodeStatus.isConnected ? .mint : .secondary
    }
}

private struct GitHubModule: View {
    @EnvironmentObject private var store: FusionStore

    /// 设计基准：GitHub 卡默认 8×4 格换算成像素；此尺寸下 f = 1。
    private static let designSize = LiveLayout.pixelDesign(columns: 8, rows: 4)

    var body: some View {
        GeometryReader { proxy in
            let f = LiveLayout.textFactor(for: proxy.size, design: Self.designSize)
            VStack(alignment: .leading, spacing: 0) {
                header(f)
                if store.githubStatus.isConnected {
                    Spacer(minLength: 6 * f)
                    GitHubInfoRow(title: tr("Account"), value: store.githubStatus.username ?? tr("Unavailable"), factor: f)
                    Spacer(minLength: 5 * f)
                    GitHubInfoRow(title: tr("Member Since"), value: store.githubStatus.accountCreatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? tr("Unavailable"), factor: f)
                    Spacer(minLength: 6 * f)
                    Divider()
                    Spacer(minLength: 6 * f)
                    HStack(spacing: 16) {
                        GitHubStatCell(title: tr("Public Repos"), value: store.githubStatus.publicRepoCount, factor: f)
                        GitHubStatCell(title: tr("Private Repos"), value: store.githubStatus.privateRepoCount, factor: f)
                        GitHubStatCell(title: tr("Total Repos"), value: store.githubStatus.totalRepoCount, factor: f)
                        GitHubStatCell(title: tr("Forks"), value: store.githubStatus.forkCount, factor: f)
                    }
                    if !store.githubStatus.recentRepositories.isEmpty {
                        Spacer(minLength: 7 * f)
                        Divider()
                        Spacer(minLength: 5 * f)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tr("Recently Updated"))
                                .font(.system(size: 11 * f, weight: .semibold))
                            Spacer(minLength: 4 * f)
                            VStack(alignment: .leading, spacing: 5 * f) {
                                ForEach(store.githubStatus.recentRepositories.prefix(3)) { repo in
                                    GitHubRepoRow(repo: repo, factor: f)
                                }
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 6 * f)
                    Text(tr(store.githubStatus.message))
                        .font(.system(size: 12 * f))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6 * f)
                Text(tr("Updated {s}", store.githubStatus.sampledAt.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10 * f))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func header(_ f: CGFloat) -> some View {
        HStack {
            Label(tr("GitHub Overview"), systemImage: "octagon")
                .font(.system(size: 15 * f, weight: .semibold))
            Spacer(minLength: 8)
            Text(statusTitle)
                .font(.system(size: 11 * f, weight: .semibold))
                .foregroundStyle(statusTint)
        }
    }

    private var statusTitle: String {
        store.githubStatus.isConnected ? tr("Connected") : tr("Unavailable")
    }

    private var statusTint: Color {
        store.githubStatus.isConnected ? .mint : .secondary
    }
}

private struct GitHubInfoRow: View {
    let title: String
    let value: String
    let factor: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12 * factor))
                .layoutPriority(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12 * factor, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct GitHubStatCell: View {
    let title: String
    let value: Int?
    let factor: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * factor) {
            Text(value.map(String.init) ?? "–")
                .font(.system(size: 18 * factor, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(size: 10 * factor))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GitHubRepoRow: View {
    let repo: GitHubRepositoryInfo
    let factor: CGFloat

    var body: some View {
        HStack(spacing: 6 * factor) {
            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 10 * factor))
                .foregroundStyle(.secondary)
            Text(repo.name)
                .lineLimit(1)
                .font(.system(size: 11 * factor, weight: .medium))
            if let language = repo.language {
                Text(language)
                    .lineLimit(1)
                    .font(.system(size: 10 * factor))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(repo.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
                .lineLimit(1)
                .font(.system(size: 10 * factor))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MakerWorldModule: View {
    @EnvironmentObject private var store: FusionStore

    /// 设计基准：MakerWorld 卡默认 8×4 格换算成像素；此尺寸下 f = 1。
    private static let designSize = LiveLayout.pixelDesign(columns: 8, rows: 4)

    var body: some View {
        GeometryReader { proxy in
            let f = LiveLayout.textFactor(for: proxy.size, design: Self.designSize)
            VStack(alignment: .leading, spacing: 0) {
                header(f)
                if store.makerWorldStatus.isConnected {
                    Spacer(minLength: 6 * f)
                    VStack(alignment: .leading, spacing: 2 * f) {
                        Text(store.makerWorldStatus.displayName ?? tr("Unavailable"))
                            .font(.system(size: 13 * f, weight: .semibold))
                        if let handle = store.makerWorldStatus.handle {
                            Text("@\(handle)")
                                .font(.system(size: 11 * f))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6 * f)
                    Divider()
                    Spacer(minLength: 6 * f)
                    HStack(spacing: 16) {
                        MakerWorldStatCell(title: tr("Followers"), value: store.makerWorldStatus.fanCount, factor: f)
                        MakerWorldStatCell(title: tr("Following"), value: store.makerWorldStatus.followCount, factor: f)
                        MakerWorldStatCell(title: tr("Likes"), value: store.makerWorldStatus.likeCount, factor: f)
                        MakerWorldStatCell(title: tr("Collections"), value: store.makerWorldStatus.collectionCount, factor: f)
                    }
                    Spacer(minLength: 5 * f)
                    HStack(spacing: 16) {
                        MakerWorldStatCell(title: tr("Models"), value: store.makerWorldStatus.designCount, factor: f)
                        MakerWorldStatCell(title: tr("Downloads"), value: store.makerWorldStatus.designDownloadCount, factor: f)
                        MakerWorldStatCell(title: tr("Prints"), value: store.makerWorldStatus.designPrintCount, factor: f)
                        MakerWorldStatCell(title: tr("Model List"), value: store.makerWorldStatus.models.isEmpty ? nil : store.makerWorldStatus.models.count, factor: f)
                    }
                    if !store.makerWorldStatus.models.isEmpty {
                        Spacer(minLength: 7 * f)
                        Divider()
                        Spacer(minLength: 5 * f)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tr("Recently Updated Models"))
                                .font(.system(size: 11 * f, weight: .semibold))
                            Spacer(minLength: 4 * f)
                            VStack(alignment: .leading, spacing: 5 * f) {
                                ForEach(store.makerWorldStatus.models.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }.prefix(3)) { model in
                                    MakerWorldModelRow(model: model, factor: f)
                                }
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 6 * f)
                    Text(tr(store.makerWorldStatus.message))
                        .font(.system(size: 12 * f))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6 * f)
                Text(tr("Updated {s}", store.makerWorldStatus.sampledAt.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10 * f))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func header(_ f: CGFloat) -> some View {
        HStack {
            Label(tr("MakerWorld Overview"), systemImage: "cube.transparent")
                .font(.system(size: 15 * f, weight: .semibold))
            Spacer(minLength: 8)
            Text(statusTitle)
                .font(.system(size: 11 * f, weight: .semibold))
                .foregroundStyle(statusTint)
        }
    }

    private var statusTitle: String {
        store.makerWorldStatus.isConnected ? tr("Connected") : tr("Unavailable")
    }

    private var statusTint: Color {
        store.makerWorldStatus.isConnected ? .mint : .secondary
    }
}

private struct MakerWorldStatCell: View {
    let title: String
    let value: Int?
    let factor: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * factor) {
            Text(value.map(String.init) ?? "–")
                .font(.system(size: 18 * factor, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(size: 10 * factor))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MakerWorldModelRow: View {
    let model: MakerWorldModelInfo
    let factor: CGFloat

    var body: some View {
        HStack(spacing: 6 * factor) {
            Text(model.title)
                .lineLimit(1)
                .font(.system(size: 11 * factor, weight: .medium))
                .layoutPriority(1)
            Spacer(minLength: 4)
            Label("\(model.likeCount)", systemImage: "hand.thumbsup")
                .font(.system(size: 10 * factor).monospacedDigit())
                .foregroundStyle(.secondary)
            Label("\(model.downloadCount)", systemImage: "arrow.down.circle")
                .font(.system(size: 10 * factor).monospacedDigit())
                .foregroundStyle(.secondary)
            Label("\(model.printCount)", systemImage: "printer")
                .font(.system(size: 10 * factor).monospacedDigit())
                .foregroundStyle(.secondary)
            Text(model.updatedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
                .lineLimit(1)
                .font(.system(size: 10 * factor))
                .foregroundStyle(.secondary)
        }
    }
}

private struct HarnessModule: View {
    @EnvironmentObject private var store: FusionStore

    private static let balanceMessage = tr("Check your balance on the DeepSeek console")
    /// 设计基准尺寸（近似 Harness 卡的 8×4 格）。
    private static let designSize = CGSize(width: 800, height: 448)

    var body: some View {
        GeometryReader { proxy in
            let f = Self.textFactor(for: proxy.size)
            let status = store.harnessStatus
            VStack(alignment: .leading, spacing: 0) {
                headerRow(f)
                if status.isAvailable {
                    dividerRow(f)
                    Spacer(minLength: 4 * f)
                    infoRow(title: tr("Model / Provider"), value: modelLine, factor: f)
                    Spacer(minLength: 6 * f)
                    statsRow(status: status, factor: f)
                    Spacer(minLength: 6 * f)
                    infoRow(title: tr("API Balance / Quota"), value: Self.balanceMessage, factor: f)
                    if !status.recentSessions.isEmpty {
                        Spacer(minLength: 6 * f)
                        recentBlock(status: status, factor: f)
                    }
                    Spacer(minLength: 6 * f)
                    Text(costFootnote)
                        .font(.system(size: 10 * f))
                        .foregroundStyle(.secondary)
                } else {
                    Spacer(minLength: 4 * f)
                    Text(tr(status.message))
                        .font(.system(size: 12 * f))
                        .foregroundStyle(.secondary)
                }
                // 剩余空间由上面的多个弹性空隙均分，让内容纵向撑满卡片。
                Spacer(minLength: 4 * f)
                dividerRow(f)
                Text(tr("Updated {s}", status.sampledAt.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10 * f))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    /// 字号基准：按卡片与设计尺寸的比例缩放，等比、不变形。
    private static func textFactor(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(2.0, max(0.45, min(size.width / designSize.width, size.height / designSize.height)))
    }

    private func headerRow(_ f: CGFloat) -> some View {
        HStack {
            Label(tr("DeepSeek Harness Status"), systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15 * f, weight: .semibold))
            Spacer(minLength: 8)
            Text(statusTitle)
                .font(.system(size: 11 * f, weight: .semibold))
                .foregroundStyle(statusTint)
        }
    }

    private func dividerRow(_ f: CGFloat) -> some View {
        Divider().padding(.vertical, 5 * f)
    }

    private func infoRow(title: String, value: String, factor f: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12 * f))
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12 * f, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func statsRow(status: HarnessStatusSnapshot, factor f: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statCell(title: tr("Active Sessions"), value: "\(status.activeSessionCount)", factor: f)
            statCell(title: tr("Today's Cost"), value: costText(status.cost?.todayCost), factor: f)
            statCell(title: tr("This Week's Cost"), value: costText(status.cost?.weekCost), factor: f)
        }
    }

    private func statCell(title: String, value: String, factor f: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * f) {
            Text(value)
                .font(.system(size: 18 * f, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(size: 10 * f))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentBlock(status: HarnessStatusSnapshot, factor f: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * f) {
            Text(tr("Recent Tasks"))
                .font(.system(size: 11 * f, weight: .semibold))
            ForEach(status.recentSessions.prefix(3)) { session in
                taskRow(session: session, factor: f)
            }
        }
    }

    private func taskRow(session: HarnessSessionStatus, factor f: CGFloat) -> some View {
        HStack(spacing: 6 * f) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10 * f))
                .foregroundStyle(.secondary)
            Text(session.title)
                .font(.system(size: 11 * f, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let model = session.model {
                Text(model)
                    .font(.system(size: 10 * f).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(session.updatedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                .font(.system(size: 10 * f))
                .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        let status = store.harnessStatus
        if !status.isAvailable { return tr("Unavailable") }
        if status.isRunning { return status.activeSessionCount > 0 ? tr("Running") : tr("Online") }
        return tr("Not Running")
    }

    private var statusTint: Color {
        store.harnessStatus.isAvailable && store.harnessStatus.isRunning ? .mint : .secondary
    }

    private var modelLine: String {
        let parts = [store.harnessStatus.provider ?? "", store.harnessStatus.model ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? tr("Unavailable") : parts.joined(separator: " · ")
    }

    private func costText(_ amount: Double?) -> String {
        store.harnessStatus.cost?.formatted(amount) ?? tr("No Local Cost Data Yet")
    }

    private var costFootnote: String {
        let base = tr("Reads only local non-sensitive metadata — never keys or conversation content.")
        guard store.harnessStatus.cost?.convertedFromUSD == true else { return base }
        return tr("Ledger costs are recorded in USD and converted to ¥ at the ledger exchange rate · only non-sensitive metadata is read.")
    }
}
