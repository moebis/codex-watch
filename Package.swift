// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexWatch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexWatch", targets: ["CodexWatch"])],
    targets: [
        .executableTarget(name: "CodexWatch"),
        .testTarget(name: "CodexWatchTests", dependencies: ["CodexWatch"])
    ],
    swiftLanguageVersions: [.v5]
)
