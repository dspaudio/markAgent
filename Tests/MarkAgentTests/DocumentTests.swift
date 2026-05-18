import XCTest
@testable import ma

final class DocumentTests: XCTestCase {
    @MainActor
    func testDefaultViewModeIsRawEdit() {
        let document = MarkdownDocument()

        XCTAssertEqual(document.viewMode, .rawEdit)
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
