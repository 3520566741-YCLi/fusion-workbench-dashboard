// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FusionWorkbench",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "FusionWorkbench", targets: ["FusionWorkbench"])
    ],
    targets: [
        .executableTarget(name: "FusionWorkbench"),
        .testTarget(name: "FusionWorkbenchTests", dependencies: ["FusionWorkbench"])
    ]
)
