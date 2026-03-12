// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkAgent",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0"),
        .package(url: "https://github.com/appstefan/highlightswift.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "ma",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "HighlightSwift", package: "highlightswift"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MarkAgentTests",
            dependencies: ["ma"],
            path: "Tests/MarkAgentTests"
        ),
    ]
)
