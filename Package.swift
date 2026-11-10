// swift-tools-version: 6.0
import PackageDescription

// The engine tests run without launching Board or changing its Xcode project.
let package = Package(
    name: "BoardGamingEngine",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "BoardGamingEngine", path: "Board/Gaming"),
        .testTarget(name: "BoardGamingEngineTests", dependencies: ["BoardGamingEngine"], path: "Tests/Gaming")
    ]
)
