// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "drift-scorecard",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "DriftCore"),
        .executableTarget(name: "drift-scorecard", dependencies: ["DriftCore"]),
        .executableTarget(name: "make-samples", dependencies: ["DriftCore"]),
        .executableTarget(name: "drift-tests", dependencies: ["DriftCore"]),
    ]
)
