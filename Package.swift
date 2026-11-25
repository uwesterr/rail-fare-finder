// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RailFareFinder",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RailFareFinder", targets: ["RailFinder"])],
    targets: [
        .target(name: "RailCore"),
        .executableTarget(name: "RailFinder", dependencies: ["RailCore"]),
        .testTarget(name: "RailCoreTests", dependencies: ["RailCore"])
    ]
)
