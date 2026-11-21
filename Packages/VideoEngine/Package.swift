// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VideoEngine",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [.library(name: "VideoEngine", targets: ["VideoEngine"])],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "0.1.9")
    ],
    targets: [
        .target(name: "VideoEngine", dependencies: [
            .product(name: "Transformers", package: "swift-transformers")
        ], resources: [.copy("Resources")])
    ]
)
