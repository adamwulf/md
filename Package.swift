// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "md",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MarkdownKit", targets: ["MarkdownKit"]),
        .executable(name: "md", targets: ["md"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-cmark", from: "0.7.1")
    ],
    targets: [
        .target(
            name: "MarkdownKit",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark")
            ]
        ),
        .executableTarget(
            name: "md",
            dependencies: [
                "MarkdownKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MarkdownKitTests",
            dependencies: ["MarkdownKit"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: [
                "md",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
