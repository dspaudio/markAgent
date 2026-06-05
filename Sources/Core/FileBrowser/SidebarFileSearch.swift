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

struct SidebarSearchRequest: Equatable, Sendable {
    let id: UUID
    let mode: SidebarSearchMode
}

@MainActor
@Observable
final class SidebarSearchCommandCenter {
    private(set) var request: SidebarSearchRequest?

    func focus(_ mode: SidebarSearchMode) {
        request = SidebarSearchRequest(id: UUID(), mode: mode)
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

    static func search(
        root: URL,
        query: String,
        mode: SidebarSearchMode,
        includeHidden: Bool = false
    ) async throws -> [SidebarSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return try await Task.detached(priority: .userInitiated) {
            switch mode {
            case .files:
                let entries = try searchableEntries(in: root, includeHidden: includeHidden)
                return fileMatches(entries: entries, root: root, query: normalizedQuery)
            case .grep:
                if let results = try ripgrepMatches(root: root, query: normalizedQuery, includeHidden: includeHidden) {
                    return results
                }
                return try grepMatches(root: root, query: normalizedQuery, includeHidden: includeHidden)
            }
        }.value
    }

    private static func searchableEntries(in root: URL, includeHidden: Bool) throws -> [FileEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [FileEntry] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let entry = entry(for: url)
            if entry.isDirectory, shouldSkipDirectory(entry.name, includeHidden: includeHidden) {
                enumerator.skipDescendants()
                continue
            }
            entries.append(entry)
        }
        return entries
    }

    private static func shouldSkipDirectory(_ name: String, includeHidden: Bool) -> Bool {
        if includeHidden, name == ".git" {
            return false
        }
        return ignoredDirectoryNames.contains(name)
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

    private static func grepMatches(root: URL, query: String, includeHidden: Bool) throws -> [SidebarSearchResult] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        let needle = query.lowercased()
        var results: [SidebarSearchResult] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let entry = entry(for: url)

            if entry.isDirectory {
                if shouldSkipDirectory(entry.name, includeHidden: includeHidden) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard !entry.isImage else { continue }
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

    private static func ripgrepMatches(root: URL, query: String, includeHidden: Bool) throws -> [SidebarSearchResult]? {
        guard let executableURL = RipgrepTool.executableURL() else { return nil }
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ripgrepArguments(query: query, root: root, includeHidden: includeHidden)

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()

        switch process.terminationStatus {
        case 0:
            return try parseRipgrepMatches(outputData, root: root)
        case 1:
            return []
        default:
            return nil
        }
    }

    private static func ripgrepArguments(query: String, root: URL, includeHidden: Bool) -> [String] {
        var arguments = [
            "--json",
            "--color", "never",
            "--max-count", "1",
            "--max-filesize", "\(maxFileBytes)",
            "--glob", "!node_modules/**",
            "--glob", "!.build/**",
            "--glob", "!DerivedData/**",
        ]

        if includeHidden {
            arguments.append("--hidden")
        }

        arguments += ["--", query, root.path]
        return arguments
    }

    private static func parseRipgrepMatches(_ data: Data, root: URL) throws -> [SidebarSearchResult] {
        let output = String(decoding: data, as: UTF8.self)
        var results: [SidebarSearchResult] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            try Task.checkCancellation()
            guard let lineData = String(line).data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "match",
                  let data = json["data"] as? [String: Any],
                  let path = data["path"] as? [String: Any],
                  let pathText = path["text"] as? String,
                  let lineNumber = data["line_number"] as? Int,
                  let lines = data["lines"] as? [String: Any],
                  let lineText = lines["text"] as? String
            else {
                continue
            }

            let url = URL(fileURLWithPath: pathText)
            let entry = entry(for: url)
            let detail = "\(lineNumber): \(lineText.trimmingCharacters(in: .whitespacesAndNewlines))"
            results.append(SidebarSearchResult(
                entry: entry,
                relativePath: relativePath(for: url, root: root),
                detail: detail,
                score: lineNumber
            ))

            if results.count >= maxResults {
                break
            }
        }

        return results.sorted(by: sortResults)
    }

    private static func firstContentMatch(in url: URL, needle: String) throws -> (lineNumber: Int, detail: String)? {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maxFileBytes + 1) ?? Data()
        guard data.count <= maxFileBytes, !data.contains(0) else { return nil }
        let source = String(decoding: data, as: UTF8.self)

        for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            try Task.checkCancellation()
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
