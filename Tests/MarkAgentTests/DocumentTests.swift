import XCTest
@testable import ma

final class DocumentTests: XCTestCase {
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
}
