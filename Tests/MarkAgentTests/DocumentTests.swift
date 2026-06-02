import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ma

final class DocumentTests: XCTestCase {
    @MainActor
    func testDefaultViewModeIsRawEdit() {
        let document = MarkdownDocument()

        XCTAssertEqual(document.viewMode, .rawEdit)
    }

    @MainActor
    func testInitialLargeLoadSkipsAutomaticDiff() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgentLargeLoadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("history.md")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try largeMarkdown(lineCount: 70_000).write(to: fileURL, atomically: true, encoding: .utf8)

        let document = MarkdownDocument()
        document.load(from: fileURL)

        XCTAssertTrue(document.isLoaded)
        XCTAssertNil(document.diffResult)
        XCTAssertFalse(document.showDiff)
        XCTAssertNil(document.previousContent)
    }

    @MainActor
    func testSmallExternalUpdateStillComputesDiff() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgentSmallDiffTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("note.md")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "first\nsecond\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = MarkdownDocument()
        document.load(from: fileURL)

        try "first\nchanged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        document.load(from: fileURL)

        await waitUntil {
            document.diffResult != nil
        }

        XCTAssertEqual(document.diffResult?.addedCount, 1)
        XCTAssertEqual(document.diffResult?.removedCount, 1)
        XCTAssertTrue(document.showDiff)
    }

    @MainActor
    func testLargeExternalUpdateSkipsAutomaticDiff() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgentLargeDiffTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("history.md")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "small\nfile\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = MarkdownDocument()
        document.load(from: fileURL)

        try largeMarkdown(lineCount: 70_000).write(to: fileURL, atomically: true, encoding: .utf8)
        document.load(from: fileURL)

        XCTAssertNil(document.diffResult)
        XCTAssertFalse(document.showDiff)
        XCTAssertNil(document.previousContent)
    }

    @MainActor
    func testPlainTextFileDisablesPreview() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_markagent.swift")
        try "print(\"Hello\")".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let document = MarkdownDocument()
        document.load(from: tempFile)

        XCTAssertFalse(document.supportsPreview)
        XCTAssertEqual(document.viewMode, .rawEdit)
    }

    func testDiffCanTreatEmptyOldContentAsAdded() {
        let diff = DiffEngine.compute(old: "", new: "first\nsecond", emptyOldIsAllAdded: true)

        XCTAssertEqual(diff.addedCount, 2)
        XCTAssertEqual(diff.removedCount, 0)
    }

    func testResolveValidPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_markagent.md")
        try "# Test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = MarkdownDocument.resolveFileURL(from: tempFile.path)
        switch result {
        case .success(let url):
            XCTAssertEqual(url.path, tempFile.path)
        case .failure:
            XCTFail("Expected success but got failure")
        }
    }

    func testResolveInvalidPath() {
        let result = MarkdownDocument.resolveFileURL(from: "/nonexistent/file.md")
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .fileNotFound("/nonexistent/file.md"))
        }
    }

    func testMarkdownImageResolvesRelativePathFromDocumentDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgentImageTests-\(UUID().uuidString)", isDirectory: true)
        let assetsDir = tempDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let imageURL = assetsDir.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let reference = MarkdownImageReference.resolve(
            source: "assets/shot.png",
            altText: "screenshot",
            baseURL: tempDir
        )

        XCTAssertEqual(reference.resolvedURL?.standardizedFileURL, imageURL.standardizedFileURL)
        XCTAssertFalse(reference.isMissing)
    }

    func testMarkdownImageLineParserFindsBrokenImagePath() {
        let baseURL = URL(fileURLWithPath: "/tmp/markagent")
        let reference = MarkdownImageLineParser.firstImage(
            in: "![issue screenshot](screenshots/missing.png)",
            baseURL: baseURL
        )

        XCTAssertEqual(reference?.source, "screenshots/missing.png")
        XCTAssertEqual(reference?.altText, "issue screenshot")
        XCTAssertTrue(reference?.isMissing == true)
        XCTAssertEqual(reference?.resolvedURL?.path, "/tmp/markagent/screenshots/missing.png")
    }

    func testFileEntryRecognizesImageExtensions() {
        XCTAssertTrue(FileEntry.isImageURL(URL(fileURLWithPath: "/tmp/screenshot.PNG")))
        XCTAssertTrue(FileEntry.isImageURL(URL(fileURLWithPath: "/tmp/photo.heic")))
        XCTAssertFalse(FileEntry.isImageURL(URL(fileURLWithPath: "/tmp/readme.md")))
    }

    func testMarkdownImageThumbnailLoaderDownsamplesLargeImages() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgentThumbnailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let imageURL = tempDir.appendingPathComponent("large.png")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try makePNG(width: 1600, height: 900, at: imageURL)

        let thumbnail = try XCTUnwrap(MarkdownImageThumbnailLoader.thumbnail(for: imageURL, maxPixelSize: 200))

        XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 200)
    }

    func testSidebarTextPreviewReadsOnlyConfiguredPrefix() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgentTextPreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("large.md")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try String(repeating: "a", count: 128).write(to: fileURL, atomically: true, encoding: .utf8)

        let preview = try loadTextPreview(from: fileURL, byteLimit: 32)

        XCTAssertTrue(preview.hasPrefix(String(repeating: "a", count: 32)))
        XCTAssertFalse(preview.hasPrefix(String(repeating: "a", count: 64)))
        XCTAssertTrue(preview.contains("미리보기"))
    }

    @MainActor
    func testRecentDocumentStoreMovesExistingDocumentToFront() {
        let suiteName = "RecentDocumentStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = RecentDocumentStore(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/first.md")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        store.record(url: first)
        store.record(url: second)
        store.record(url: first)

        XCTAssertEqual(store.documents.map(\.path), [first.path, second.path])
    }
}

private func largeMarkdown(lineCount: Int) -> String {
    (0..<lineCount)
        .map { "line \($0)" }
        .joined(separator: "\n")
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

private func makePNG(width: Int, height: Int, at url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        XCTFail("Failed to create image context")
        return
    }

    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        XCTFail("Failed to create image destination")
        return
    }

    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        XCTFail("Failed to write PNG")
    }
}
