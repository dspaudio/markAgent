import XCTest
@testable import ma

final class MarkdownGitReferenceIndexTests: XCTestCase {
    func testFindsChangedFilesMentionedInMarkdownTextLinksCodeSpansAndLineReferences() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        let changedFiles = [
            GitChangedFile(rootURL: root, relativePath: "Sources/App/main.swift", status: " M"),
            GitChangedFile(rootURL: root, relativePath: "Sources/Core/GitDiffState.swift", status: " M"),
            GitChangedFile(rootURL: root, relativePath: "Tests/MarkAgentTests/GitDiffStateTests.swift", status: "??"),
        ]
        let markdown = """
        구현 파일은 `Sources/App/main.swift` 입니다.
        상세 diff는 [GitDiffState](Sources/Core/GitDiffState.swift)로 이동합니다.
        회귀 테스트: Tests/MarkAgentTests/GitDiffStateTests.swift:42
        """

        let ids = MarkdownGitReferenceIndex.mentionedFileIDs(in: markdown, changedFiles: changedFiles)

        XCTAssertEqual(ids, Set(changedFiles.map(\.id)))
    }

    func testDoesNotMatchEmptyInput() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        let changedFiles = [
            GitChangedFile(rootURL: root, relativePath: "Sources/App/main.swift", status: " M"),
        ]

        XCTAssertTrue(MarkdownGitReferenceIndex.mentionedFileIDs(in: "", changedFiles: changedFiles).isEmpty)
        XCTAssertTrue(MarkdownGitReferenceIndex.mentionedFileIDs(in: "Sources/App/main.swift", changedFiles: []).isEmpty)
    }

    func testRejectsPartialPathMatches() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        let changedFiles = [
            GitChangedFile(rootURL: root, relativePath: "Sources/App/main.swift", status: " M"),
        ]
        let markdown = """
        백업 파일 Sources/App/main.swift.bak 는 실제 변경 파일이 아닙니다.
        비슷한 경로 Sources/App/main.swiftExtra 도 무시해야 합니다.
        """

        let ids = MarkdownGitReferenceIndex.mentionedFileIDs(in: markdown, changedFiles: changedFiles)

        XCTAssertTrue(ids.isEmpty)
    }
}
