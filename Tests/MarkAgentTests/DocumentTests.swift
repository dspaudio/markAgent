import XCTest
@testable import ma

final class DocumentTests: XCTestCase {
    @MainActor
    func testDefaultViewModeIsRawEdit() {
        let document = MarkdownDocument()

        XCTAssertEqual(document.viewMode, .rawEdit)
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
