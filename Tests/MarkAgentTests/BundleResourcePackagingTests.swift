import Foundation
import XCTest

final class BundleResourcePackagingTests: XCTestCase {
    func testCopiesSwiftPMResourceBundlesIntoApplicationResources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot
            .appendingPathComponent("scripts/copy-swiftpm-resource-bundles.sh")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "SwiftPM 리소스 번들 복사 스크립트가 필요합니다."
        )
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleResourcePackagingTests-\(UUID().uuidString)")
        let productsDirectory = temporaryDirectory.appendingPathComponent("Products")
        let applicationRoot = temporaryDirectory.appendingPathComponent("MarkAgent.app")
        let applicationResources = applicationRoot
            .appendingPathComponent("Contents/Resources")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(
            at: productsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: applicationRoot,
            withIntermediateDirectories: true
        )

        let ghosttyBundle = productsDirectory
            .appendingPathComponent("GhosttyKit_GhosttyTerminal.bundle")
        let highlightBundle = productsDirectory
            .appendingPathComponent("HighlightSwift_HighlightSwift.bundle")
        let ignoredDirectory = productsDirectory.appendingPathComponent("NotAResource")
        for directory in [ghosttyBundle, highlightBundle, ignoredDirectory] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        try Data("ghostty".utf8).write(
            to: ghosttyBundle.appendingPathComponent("resource.txt")
        )
        try Data("highlight".utf8).write(
            to: highlightBundle.appendingPathComponent("resource.txt")
        )

        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            productsDirectory.path,
            applicationRoot.path,
        ]
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(decoding: errorData, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, errorOutput)
        XCTAssertEqual(
            try String(
                contentsOf: applicationResources
                    .appendingPathComponent("GhosttyKit_GhosttyTerminal.bundle/resource.txt"),
                encoding: .utf8
            ),
            "ghostty"
        )
        XCTAssertEqual(
            try String(
                contentsOf: applicationResources
                    .appendingPathComponent("HighlightSwift_HighlightSwift.bundle/resource.txt"),
                encoding: .utf8
            ),
            "highlight"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: applicationResources.appendingPathComponent("NotAResource").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: applicationRoot
                    .appendingPathComponent("GhosttyKit_GhosttyTerminal.bundle")
                    .path
            )
        )
    }
}
