import XCTest
@testable import ma

final class SidebarFileSearchTests: XCTestCase {
    func testFuzzyFileSearchMatchesNonContiguousCharacters() async throws {
        let root = try makeTemporaryDirectory()
        try write("Release notes", to: root.appending(path: "README.md"))
        try write("Scratch", to: root.appending(path: "scratch.txt"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "rme",
            mode: .files
        )

        XCTAssertEqual(results.map(\.entry.name), ["README.md"])
        XCTAssertEqual(results.first?.detail, "README.md")
    }

    func testBlankQueryReturnsNoSearchResults() async throws {
        let root = try makeTemporaryDirectory()
        try write("Release notes", to: root.appending(path: "README.md"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "  ",
            mode: .files
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testFuzzyFileSearchDoesNotReturnDirectories() async throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appending(path: "ReadmeFolder"), withIntermediateDirectories: true)
        try write("Release notes", to: root.appending(path: "README.md"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "readme",
            mode: .files
        )

        XCTAssertEqual(results.map(\.entry.name), ["README.md"])
    }

    func testFuzzyFileSearchSkipsIgnoredDirectories() async throws {
        let root = try makeTemporaryDirectory()
        let ignoredDirectory = root.appending(path: "node_modules")
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try write("Ignored", to: ignoredDirectory.appending(path: "README.md"))
        try write("Visible", to: root.appending(path: "README.md"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "readme",
            mode: .files
        )

        XCTAssertEqual(results.map(\.detail), ["README.md"])
    }

    func testFuzzyFileSearchShowsHiddenFilesWhenRequested() async throws {
        let root = try makeTemporaryDirectory()
        try write("SECRET=value", to: root.appending(path: ".env"))

        let hiddenResults = try await SidebarFileSearch.search(
            root: root,
            query: "env",
            mode: .files
        )
        let visibleResults = try await SidebarFileSearch.search(
            root: root,
            query: "env",
            mode: .files,
            includeHidden: true
        )

        XCTAssertTrue(hiddenResults.isEmpty)
        XCTAssertEqual(visibleResults.map(\.entry.name), [".env"])
    }

    func testGrepSearchShowsGitDirectoryContentsWhenHiddenFilesAreRequested() async throws {
        let root = try makeTemporaryDirectory()
        let gitDirectory = root.appending(path: ".git")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try write("needle in git config", to: gitDirectory.appending(path: "config"))

        let hiddenResults = try await SidebarFileSearch.search(
            root: root,
            query: "needle",
            mode: .grep
        )
        let visibleResults = try await SidebarFileSearch.search(
            root: root,
            query: "needle",
            mode: .grep,
            includeHidden: true
        )

        XCTAssertTrue(hiddenResults.isEmpty)
        XCTAssertEqual(visibleResults.map(\.relativePath), [".git/config"])
    }

    func testGrepSearchFindsContentMatchesWithLinePreview() async throws {
        let root = try makeTemporaryDirectory()
        try write("alpha\nneedle in haystack\nomega", to: root.appending(path: "notes.md"))
        try write("nothing relevant", to: root.appending(path: "other.txt"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "needle",
            mode: .grep
        )

        XCTAssertEqual(results.map(\.entry.name), ["notes.md"])
        XCTAssertEqual(results.first?.detail, "2: needle in haystack")
        XCTAssertEqual(results.first?.relativePath, "notes.md")
    }

    func testGrepSearchStoresRelativePathFromCurrentDirectory() async throws {
        let root = try makeTemporaryDirectory()
        let nested = root.appending(path: "docs")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("needle in nested file", to: nested.appending(path: "guide.md"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "needle",
            mode: .grep
        )

        XCTAssertEqual(results.map(\.entry.name), ["guide.md"])
        XCTAssertEqual(results.first?.relativePath, "docs/guide.md")
        XCTAssertEqual(results.first?.detail, "1: needle in nested file")
    }

    func testGrepSearchSkipsUnreadableFileAndKeepsReadableMatches() async throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appending(path: "unreadable"), withIntermediateDirectories: true)
        try write("needle in readable file", to: root.appending(path: "readable.md"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "needle",
            mode: .grep
        )

        XCTAssertEqual(results.map(\.entry.name), ["readable.md"])
    }

    func testEnterPreviewCandidateUsesFirstSearchResult() throws {
        let root = try makeTemporaryDirectory()
        let first = FileEntry(url: root.appending(path: "README.md"), name: "README.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let second = FileEntry(url: root.appending(path: "notes.md"), name: "notes.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let results = [
            SidebarSearchResult(entry: first, relativePath: "README.md", detail: "README.md", score: 1),
            SidebarSearchResult(entry: second, relativePath: "notes.md", detail: "notes.md", score: 2),
        ]

        XCTAssertEqual(SidebarSearchNavigation.previewCandidate(from: results), first)
    }

    func testArrowNavigationMovesSelectedSearchResult() throws {
        let root = try makeTemporaryDirectory()
        let first = FileEntry(url: root.appending(path: "README.md"), name: "README.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let second = FileEntry(url: root.appending(path: "REAM.md"), name: "REAM.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let third = FileEntry(url: root.appending(path: "RoadMapEntry.md"), name: "RoadMapEntry.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let results = [
            SidebarSearchResult(entry: first, relativePath: "README.md", detail: "README.md", score: 1),
            SidebarSearchResult(entry: second, relativePath: "REAM.md", detail: "REAM.md", score: 2),
            SidebarSearchResult(entry: third, relativePath: "RoadMapEntry.md", detail: "RoadMapEntry.md", score: 3),
        ]

        XCTAssertEqual(SidebarSearchNavigation.selectedResultID(afterMovingFrom: results[0].id, by: 1, in: results), results[1].id)
        XCTAssertEqual(SidebarSearchNavigation.selectedResultID(afterMovingFrom: results[1].id, by: 1, in: results), results[2].id)
        XCTAssertEqual(SidebarSearchNavigation.selectedResultID(afterMovingFrom: results[2].id, by: 1, in: results), results[2].id)
        XCTAssertEqual(SidebarSearchNavigation.selectedResultID(afterMovingFrom: results[1].id, by: -1, in: results), results[0].id)
        XCTAssertEqual(SidebarSearchNavigation.selectedResultID(afterMovingFrom: nil, by: 1, in: results), results[0].id)
    }

    func testEnterPreviewCandidateUsesSelectedSearchResult() throws {
        let root = try makeTemporaryDirectory()
        let first = FileEntry(url: root.appending(path: "README.md"), name: "README.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let second = FileEntry(url: root.appending(path: "REAM.md"), name: "REAM.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let results = [
            SidebarSearchResult(entry: first, relativePath: "README.md", detail: "README.md", score: 1),
            SidebarSearchResult(entry: second, relativePath: "REAM.md", detail: "REAM.md", score: 2),
        ]

        XCTAssertEqual(
            SidebarSearchNavigation.previewCandidate(from: results, selectedResultID: results[1].id, isSearching: false),
            second
        )
    }

    func testGrepSearchResultsUseSameSelectionNavigation() async throws {
        let root = try makeTemporaryDirectory()
        try write("needle first", to: root.appending(path: "alpha.md"))
        try write("needle second", to: root.appending(path: "beta.md"))

        let results = try await SidebarFileSearch.search(
            root: root,
            query: "needle",
            mode: .grep
        )
        let selectedID = SidebarSearchNavigation.selectedResultID(
            afterMovingFrom: results.first?.id,
            by: 1,
            in: results
        )

        XCTAssertEqual(results.map(\.entry.name), ["alpha.md", "beta.md"])
        XCTAssertEqual(
            SidebarSearchNavigation.previewCandidate(from: results, selectedResultID: selectedID, isSearching: false)?.name,
            "beta.md"
        )
    }

    func testEnterPreviewIgnoresStaleResultsWhileSearching() throws {
        let root = try makeTemporaryDirectory()
        let first = FileEntry(url: root.appending(path: "README.md"), name: "README.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let results = [
            SidebarSearchResult(entry: first, relativePath: "README.md", detail: "README.md", score: 1),
        ]

        XCTAssertNil(SidebarSearchNavigation.previewCandidate(from: results, isSearching: true))
    }

    func testDirectoryChangeClearsActiveSearchQuery() {
        var state = SidebarSearchStateSnapshot(
            text: "readme",
            results: [],
            isSearching: true,
            error: "old error",
            selectedResultID: "stale",
            isPreviewingResult: true
        )

        SidebarSearchStateReducer.applyDirectoryChange(to: &state)

        XCTAssertEqual(state.text, "")
        XCTAssertTrue(state.results.isEmpty)
        XCTAssertFalse(state.isSearching)
        XCTAssertNil(state.error)
        XCTAssertNil(state.selectedResultID)
        XCTAssertFalse(state.isPreviewingResult)
    }

    func testEscapeClosesPreviewBeforeClearingSearch() throws {
        let root = try makeTemporaryDirectory()
        let entry = FileEntry(url: root.appending(path: "README.md"), name: "README.md", kind: .markdown, sizeBytes: nil, modifiedAt: nil)
        let result = SidebarSearchResult(entry: entry, relativePath: "README.md", detail: "README.md", score: 1)
        var state = SidebarSearchStateSnapshot(
            text: "rme",
            results: [result],
            isSearching: false,
            error: nil,
            selectedResultID: result.id,
            isPreviewingResult: true
        )

        XCTAssertEqual(SidebarSearchStateReducer.applyEscape(to: &state), .closePreview)
        XCTAssertEqual(state.text, "rme")
        XCTAssertEqual(state.results, [result])
        XCTAssertEqual(state.selectedResultID, result.id)
        XCTAssertFalse(state.isPreviewingResult)

        XCTAssertEqual(SidebarSearchStateReducer.applyEscape(to: &state), .clearSearch)
        XCTAssertEqual(state.text, "")
        XCTAssertTrue(state.results.isEmpty)
        XCTAssertNil(state.selectedResultID)
    }

    func testDirectoryScanStillSortsDirectoriesBeforeFiles() throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appending(path: "Folder"), withIntermediateDirectories: true)
        try write("Read me", to: root.appending(path: "README.md"))

        let entries = try DirectoryScanner.scan(directory: root)

        XCTAssertEqual(entries.map(\.name), ["Folder", "README.md"])
    }

    func testDirectoryScanShowsHiddenEntriesWhenRequested() throws {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try write("SECRET=value", to: root.appending(path: ".env"))
        try write("Read me", to: root.appending(path: "README.md"))

        let hiddenEntries = try DirectoryScanner.scan(directory: root)
        let visibleEntries = try DirectoryScanner.scan(directory: root, includeHidden: true)

        XCTAssertEqual(hiddenEntries.map(\.name), ["README.md"])
        XCTAssertEqual(visibleEntries.map(\.name), [".git", ".env", "README.md"])
    }

    func testSearchLocalizationKeysExistInKoreanAndEnglish() throws {
        let keys = [
            "파일 검색",
            "내용 검색",
            "검색 표시",
            "검색 숨기기",
            "검색 지우기",
            "검색 모드",
            "내용",
            "Grep",
            "검색 중",
            "%d개 결과",
            "검색 결과",
            "검색 결과 없음",
            "숨김 파일 표시",
            "숨김 파일 숨기기",
            "File Search",
            "Content Search",
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let korean = try String(contentsOf: root.appending(path: "Sources/App/Resources/ko.lproj/Localizable.strings"), encoding: .utf8)
        let english = try String(contentsOf: root.appending(path: "Sources/App/Resources/en.lproj/Localizable.strings"), encoding: .utf8)

        for key in keys {
            XCTAssertTrue(korean.contains("\"\(key)\" ="), "Missing Korean key \(key)")
            XCTAssertTrue(english.contains("\"\(key)\" ="), "Missing English key \(key)")
        }
    }

    @MainActor
    func testSidebarSearchCommandCenterPublishesFreshRequests() {
        let commandCenter = SidebarSearchCommandCenter()

        commandCenter.focus(.files)
        let firstRequest = commandCenter.request
        commandCenter.focus(.grep)
        let secondRequest = commandCenter.request

        XCTAssertEqual(firstRequest?.mode, .files)
        XCTAssertEqual(secondRequest?.mode, .grep)
        XCTAssertNotEqual(firstRequest?.id, secondRequest?.id)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "markagent-sidebar-search-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url)
    }
}
