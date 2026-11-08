// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnagramKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AnagramModels", targets: ["AnagramModels"]),
        .library(name: "AnagramEngine", targets: ["AnagramEngine"]),
    ],
    targets: [
        .target(name: "AnagramModels"),
        .target(name: "AnagramEngine", dependencies: ["AnagramModels"]),
        .testTarget(name: "AnagramEngineTests", dependencies: ["AnagramEngine", "AnagramModels"]),
    ]
)
