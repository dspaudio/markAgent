import Foundation

enum SidebarSearchMode: String, CaseIterable, Identifiable, Sendable {
    case files
    case grep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:
            return String(localized: "파일")
        case .grep:
            return String(localized: "내용")
        }
    }
}

struct SidebarSearchResult: Identifiable, Equatable, Sendable {
    let entry: FileEntry
    let relativePath: String
    let detail: String
    let score: Int

    var id: String { "\(entry.id)-\(detail)" }
}

enum SidebarFileSearch {
    private static let maxFileBytes = 512 * 1024
    private static let maxResults = 80
    private static let ignoredDirectoryNames: Set<String> = [".git", ".build", "node_modules", "DerivedData"]

    static func search(root: URL, query: String, mode: SidebarSearchMode) async throws -> [SidebarSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return try await Task.detached(priority: .userInitiated) {
            let entries = try searchableEntries(in: root)

            switch mode {
            case .files:
                return fileMatches(entries: entries, root: root, query: normalizedQuery)
            case .grep:
                return try grepMatches(entries: entries, root: root, query: normalizedQuery)
            }
        }.value
    }

    private static func searchableEntries(in root: URL) throws -> [FileEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [FileEntry] = []
        for case let url as URL in enumerator {
            let entry = entry(for: url)
            if entry.isDirectory, ignoredDirectoryNames.contains(entry.name) {
                enumerator.skipDescendants()
                continue
            }
            entries.append(entry)
        }
        return entries
    }

    private static func entry(for url: URL) -> FileEntry {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let kind: FileEntry.Kind
        if isDirectory {
            kind = .directory
        } else if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
            kind = .markdown
        } else if FileEntry.isImageURL(url) {
            kind = .image
        } else {
            kind = .file
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileEntry(
            url: url,
            name: url.lastPathComponent,
            kind: kind,
            sizeBytes: values?.fileSize.map(Int64.init),
            modifiedAt: values?.contentModificationDate
        )
    }

    private static func fileMatches(entries: [FileEntry], root: URL, query: String) -> [SidebarSearchResult] {
        entries
            .compactMap { entry -> SidebarSearchResult? in
                guard !entry.isDirectory else { return nil }
                guard let score = fuzzyScore(entry.name, query: query) else { return nil }
                let relativePath = relativePath(for: entry.url, root: root)
                return SidebarSearchResult(
                    entry: entry,
                    relativePath: relativePath,
                    detail: relativePath,
                    score: score
                )
            }
            .sorted(by: sortResults)
            .prefix(maxResults)
            .map { $0 }
    }

    private static func grepMatches(entries: [FileEntry], root: URL, query: String) throws -> [SidebarSearchResult] {
        let needle = query.lowercased()
        var results: [SidebarSearchResult] = []

        for entry in entries where !entry.isDirectory && !entry.isImage {
            guard let match = try? firstContentMatch(in: entry.url, needle: needle) else { continue }
            results.append(SidebarSearchResult(
                entry: entry,
                relativePath: relativePath(for: entry.url, root: root),
                detail: match.detail,
                score: match.lineNumber
            ))

            if results.count >= maxResults {
                break
            }
        }

        return results.sorted(by: sortResults)
    }

    private static func firstContentMatch(in url: URL, needle: String) throws -> (lineNumber: Int, detail: String)? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maxFileBytes + 1) ?? Data()
        guard data.count <= maxFileBytes, !data.contains(0) else { return nil }
        let source = String(decoding: data, as: UTF8.self)

        for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.localizedCaseInsensitiveContains(needle) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return (offset + 1, "\(offset + 1): \(trimmed)")
            }
        }
        return nil
    }

    private static func fuzzyScore(_ candidate: String, query: String) -> Int? {
        let candidateCharacters = Array(candidate.lowercased())
        let queryCharacters = Array(query.lowercased())
        var queryIndex = queryCharacters.startIndex
        var score = 0

        for candidateIndex in candidateCharacters.indices {
            guard queryIndex < queryCharacters.endIndex else { break }
            if candidateCharacters[candidateIndex] == queryCharacters[queryIndex] {
                score += candidateIndex
                queryIndex = queryCharacters.index(after: queryIndex)
            }
        }

        guard queryIndex == queryCharacters.endIndex else { return nil }
        if candidate.lowercased().hasPrefix(query.lowercased()) {
            score -= 10
        }
        return score
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func sortResults(_ lhs: SidebarSearchResult, _ rhs: SidebarSearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.entry.name.localizedStandardCompare(rhs.entry.name) == .orderedAscending
    }
}

enum SidebarSearchNavigation {
    static func previewCandidate(from results: [SidebarSearchResult]) -> FileEntry? {
        previewCandidate(from: results, selectedResultID: nil, isSearching: false)
    }

    static func previewCandidate(from results: [SidebarSearchResult], isSearching: Bool) -> FileEntry? {
        previewCandidate(from: results, selectedResultID: nil, isSearching: isSearching)
    }

    static func previewCandidate(
        from results: [SidebarSearchResult],
        selectedResultID: SidebarSearchResult.ID?,
        isSearching: Bool
    ) -> FileEntry? {
        guard !isSearching else { return nil }
        if let selectedResultID, let selected = results.first(where: { $0.id == selectedResultID }) {
            return selected.entry
        }
        return results.first?.entry
    }

    static func selectedResultID(
        afterMovingFrom currentID: SidebarSearchResult.ID?,
        by offset: Int,
        in results: [SidebarSearchResult]
    ) -> SidebarSearchResult.ID? {
        guard !results.isEmpty else { return nil }
        guard let currentID, let currentIndex = results.firstIndex(where: { $0.id == currentID }) else {
            return results.first?.id
        }

        let nextIndex = min(max(currentIndex + offset, results.startIndex), results.index(before: results.endIndex))
        return results[nextIndex].id
    }
}

struct SidebarSearchStateSnapshot: Equatable, Sendable {
    var text: String
    var results: [SidebarSearchResult]
    var isSearching: Bool
    var error: String?
    var selectedResultID: SidebarSearchResult.ID?
    var isPreviewingResult: Bool
}

enum SidebarSearchEscapeOutcome: Equatable, Sendable {
    case none
    case closePreview
    case clearSearch
}

enum SidebarSearchStateReducer {
    static func applyDirectoryChange(to state: inout SidebarSearchStateSnapshot) {
        state.text = ""
        state.results = []
        state.isSearching = false
        state.error = nil
        state.selectedResultID = nil
        state.isPreviewingResult = false
    }

    static func applyEscape(to state: inout SidebarSearchStateSnapshot) -> SidebarSearchEscapeOutcome {
        if state.isPreviewingResult {
            state.isPreviewingResult = false
            return .closePreview
        }

        guard !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }

        state.text = ""
        state.results = []
        state.isSearching = false
        state.error = nil
        state.selectedResultID = nil
        return .clearSearch
    }
}
