// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NeodragonNativeCheck",
    platforms: [.macOS("15.0")],
    dependencies: [.package(path: "../../../Packages/VideoEngine")],
    targets: [.executableTarget(name: "NeodragonNativeCheck", dependencies: [
        .product(name: "VideoEngine", package: "VideoEngine")
    ])]
)
