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
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ma",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "HighlightSwift", package: "highlightswift"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
            ],
            path: "Sources",
            exclude: ["App/Info.plist", "App/Resources"]
        ),
        .testTarget(
            name: "MarkAgentTests",
            dependencies: ["ma"],
            path: "Tests/MarkAgentTests"
        ),
    ]
)
