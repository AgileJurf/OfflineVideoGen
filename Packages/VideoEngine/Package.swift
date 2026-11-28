// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VideoEngine",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [.library(name: "VideoEngine", targets: ["VideoEngine"])],
    targets: [
        .target(name: "VideoEngine", resources: [.process("Resources")])
    ]
)
