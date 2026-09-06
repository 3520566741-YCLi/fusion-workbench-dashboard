import Foundation

enum DashboardCanvasLimits {
    static let columns = 100
    static let rows = 100
    static let maximumVisibleModules = 40
    static let cellWidth: CGFloat = 96
    static let rowHeight: CGFloat = 108
}

struct Workspace: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
    let subtitle: String
    let status: WorkspaceStatus
    let completion: Double
    let focus: String
    let artifacts: [Artifact]

    static let samples: [Workspace] = [
        Workspace(
            id: UUID(),
            name: "Fusion Workbench",
            symbol: "circle.hexagongrid.fill",
            subtitle: "Building the first data dashboard",
            status: .active,
            completion: 0.42,
            focus: "Finish the three-column workbench and local status sampling",
            artifacts: [
                Artifact(name: "Product structure", detail: "Three-column dashboard · v1", symbol: "rectangle.3.group.fill"),
                Artifact(name: "System monitoring", detail: "CPU / memory / disk", symbol: "waveform.path.ecg"),
                Artifact(name: "Sidecar mode", detail: "iPad mirrors the Mac app", symbol: "rectangle.on.rectangle"),
            ]
        ),
        Workspace(
            id: UUID(),
            name: "Codex Workbench",
            symbol: "puzzlepiece.extension.fill",
            subtitle: "Kept unchanged for comparison",
            status: .paused,
            completion: 0.78,
            focus: "Do not modify; awaiting the Fusion comparison",
            artifacts: [Artifact(name: "Original workbench", detail: "Kept untouched", symbol: "lock.fill")]
        ),
        Workspace(
            id: UUID(),
            name: "Travel Atlas",
            symbol: "globe.asia.australia.fill",
            subtitle: "A future data-card example",
            status: .idle,
            completion: 0.12,
            focus: "Map and weather entry points to come",
            artifacts: [Artifact(name: "Nullschool", detail: "External weather entry point", symbol: "wind")]
        )
    ]
}

enum WorkspaceStatus: String, Hashable {
    case active = "In Progress"
    case paused = "Paused"
    case idle = "Idle"

    var tintName: String {
        switch self {
        case .active: "mint"
        case .paused: "orange"
        case .idle: "secondary"
        }
    }
}

struct Artifact: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let detail: String
    let symbol: String
}

struct SystemMetrics: Equatable {
    var cpuPercent: Double?
    var cpuPerformanceCores: Int?
    var cpuEfficiencyCores: Int?
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var gpu: GPUMetrics?
    var diskAvailableBytes: Int64
    var diskTotalBytes: Int64
    var thermalState: ProcessInfo.ThermalState
    var sampledAt: Date

    static let unavailable = SystemMetrics(
        cpuPercent: nil,
        cpuPerformanceCores: nil,
        cpuEfficiencyCores: nil,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        gpu: nil,
        diskAvailableBytes: 0,
        diskTotalBytes: 0,
        thermalState: ProcessInfo.processInfo.thermalState,
        sampledAt: .now
    )

    var memoryPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1, Double(memoryUsedBytes) / Double(memoryTotalBytes))
    }

    var diskPercent: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return min(1, 1 - Double(diskAvailableBytes) / Double(diskTotalBytes))
    }
}

struct GPUMetrics: Equatable {
    let coreCount: Int?
    let deviceUtilization: Double?
    let rendererUtilization: Double?
    let tilerUtilization: Double?
    let allocatedMemoryBytes: Int64?
    let usedMemoryBytes: Int64?
}

enum DashboardModuleID: String, CaseIterable, Codable, Identifiable {
    case weather, system, codex, commandCode, github, makerWorld, harness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: tr("Nullschool Earth Weather")
        case .system: tr("Mac Status")
        case .codex: tr("Codex Status")
        case .commandCode: tr("Command Code Status")
        case .github: tr("GitHub Overview")
        case .makerWorld: tr("MakerWorld Overview")
        case .harness: tr("DeepSeek Harness Status")
        }
    }

    var symbol: String {
        switch self {
        case .weather: "globe.americas.fill"
        case .system: "desktopcomputer"
        case .codex: "sparkles"
        case .commandCode: "terminal.fill"
        case .github: "octagon"
        case .makerWorld: "cube.transparent"
        case .harness: "antenna.radiowaves.left.and.right"
        }
    }

    var minimumSize: (width: Int, height: Int) {
        switch self {
        case .weather: (4, 2)
        case .system: (3, 4)
        case .codex: (3, 2)
        case .commandCode: (3, 2)
        case .github: (3, 2)
        case .makerWorld: (3, 2)
        case .harness: (4, 4)
        }
    }

    /// Design size of this module in the default layout (width x height, in cells).
    /// Card content scales around this: at design size the content renders 1:1,
    /// and scales with the card when it is enlarged/shrunk (auto-arrange included).
    var designSize: (width: Int, height: Int) {
        if let item = DashboardLayoutItem.defaults.first(where: { $0.id == self }) {
            return (item.width, item.height)
        }
        return minimumSize
    }
}

struct DashboardLayoutItem: Codable, Identifiable, Equatable {
    let id: DashboardModuleID
    var isVisible: Bool
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    static let defaults: [DashboardLayoutItem] = [
        DashboardLayoutItem(id: .weather, isVisible: true, x: 0, y: 0, width: 8, height: 4),
        DashboardLayoutItem(id: .system, isVisible: true, x: 8, y: 0, width: 4, height: 6),
        DashboardLayoutItem(id: .codex, isVisible: true, x: 0, y: 4, width: 4, height: 3),
        DashboardLayoutItem(id: .commandCode, isVisible: true, x: 4, y: 4, width: 4, height: 3),
        DashboardLayoutItem(id: .github, isVisible: true, x: 0, y: 7, width: 8, height: 4),
        DashboardLayoutItem(id: .makerWorld, isVisible: true, x: 0, y: 11, width: 8, height: 4),
        DashboardLayoutItem(id: .harness, isVisible: true, x: 0, y: 15, width: 8, height: 4)
    ]
}

struct DashboardLayoutPreview: Equatable {
    let id: DashboardModuleID
    let item: DashboardLayoutItem
    let isValid: Bool
    let isResize: Bool
}
