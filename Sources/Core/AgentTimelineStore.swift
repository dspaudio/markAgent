import Foundation

enum AgentTimelineEventKind: String, Codable, Equatable {
    case terminal = "terminal_created"
    case markdown = "markdown_opened"
    case gitDiff = "git_diff_focused"
    case commit = "commit_created"
}

struct AgentTimelineCommit: Codable, Equatable {
    let hash: String
    let shortHash: String
    let subject: String
    let author: String
    let committedAt: String
}

struct AgentTimelineChangedFile: Codable, Equatable {
    let path: String
    let insertions: Int
    let deletions: Int
}

struct AgentTimelineChanges: Codable, Equatable {
    let files: [AgentTimelineChangedFile]
    let insertions: Int
    let deletions: Int
}

struct AgentTimelineCommitSnapshot: Codable, Equatable {
    let commit: AgentTimelineCommit
    let changes: AgentTimelineChanges
}

struct AgentTimelineEvent: Identifiable, Codable, Equatable {
    let version: Int
    let id: UUID
    let kind: AgentTimelineEventKind
    let title: String
    let detail: String
    let timestamp: Date
    let source: String
    let repositoryRoot: String?
    let commit: AgentTimelineCommit?
    let changes: AgentTimelineChanges?

    init(
        version: Int = 1,
        id: UUID = UUID(),
        kind: AgentTimelineEventKind,
        title: String,
        detail: String,
        timestamp: Date,
        source: String = "MarkAgent",
        repositoryRoot: String? = nil,
        commit: AgentTimelineCommit? = nil,
        changes: AgentTimelineChanges? = nil
    ) {
        self.version = version
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.source = source
        self.repositoryRoot = repositoryRoot
        self.commit = commit
        self.changes = changes
    }
}

enum AgentTimelineAction {
    case terminalCreated(directory: URL)
    case markdownOpened(url: URL)
    case gitDiffFocused(relativePath: String)
    case commitCreated(AgentTimelineCommitSnapshot)
}

@MainActor
@Observable
final class AgentTimelineStore {
    private(set) var events: [AgentTimelineEvent] = []

    private let limit: Int
    private let now: () -> Date
    private var repositoryRoot: URL?
    private var commitSnapshotTask: Task<Void, Never>?

    init(limit: Int = 100, now: @escaping @autoclosure () -> Date = Date()) {
        self.limit = max(1, limit)
        self.now = now
    }

    func configureRepositoryRoot(_ root: URL?) {
        let standardizedRoot = root?.standardizedFileURL
        guard repositoryRoot != standardizedRoot else { return }
        repositoryRoot = standardizedRoot

        guard let standardizedRoot else { return }
        let loadedEvents = loadPersistedEvents(repositoryRoot: standardizedRoot)
        mergeLoadedEvents(loadedEvents)
        regenerateMarkdownSummary()
    }

    func record(_ action: AgentTimelineAction) {
        let event = event(for: action)
        events.insert(event, at: 0)
        trimEventsToLimit()
        persist(event)
    }

    func recordLatestCommitIfNeeded(repositoryRoot root: URL) {
        let standardizedRoot = root.standardizedFileURL
        configureRepositoryRoot(standardizedRoot)
        commitSnapshotTask?.cancel()

        commitSnapshotTask = Task { [standardizedRoot] in
            let snapshot = await Task.detached(priority: .utility) {
                try? Self.loadLatestCommitSnapshot(repositoryRoot: standardizedRoot)
            }.value

            guard !Task.isCancelled, let snapshot else { return }
            guard !self.events.contains(where: { $0.commit?.hash == snapshot.commit.hash }) else { return }
            self.record(.commitCreated(snapshot))
        }
    }

    private func event(for action: AgentTimelineAction) -> AgentTimelineEvent {
        let repositoryRootPath = repositoryRoot?.path

        switch action {
        case .terminalCreated(let directory):
            return AgentTimelineEvent(
                kind: .terminal,
                title: "터미널 탭",
                detail: directory.path,
                timestamp: now(),
                repositoryRoot: repositoryRootPath
            )
        case .markdownOpened(let url):
            return AgentTimelineEvent(
                kind: .markdown,
                title: "마크다운 열림",
                detail: url.lastPathComponent,
                timestamp: now(),
                repositoryRoot: repositoryRootPath
            )
        case .gitDiffFocused(let relativePath):
            return AgentTimelineEvent(
                kind: .gitDiff,
                title: "Diff 포커스",
                detail: relativePath,
                timestamp: now(),
                repositoryRoot: repositoryRootPath
            )
        case .commitCreated(let snapshot):
            return AgentTimelineEvent(
                kind: .commit,
                title: "커밋 생성",
                detail: snapshot.commit.subject,
                timestamp: now(),
                repositoryRoot: repositoryRootPath,
                commit: snapshot.commit,
                changes: snapshot.changes
            )
        }
    }

    private func mergeLoadedEvents(_ loadedEvents: [AgentTimelineEvent]) {
        var uniqueEvents: [UUID: AgentTimelineEvent] = [:]
        for event in events + loadedEvents {
            uniqueEvents[event.id] = event
        }
        events = uniqueEvents.values
            .sorted { $0.timestamp > $1.timestamp }
        trimEventsToLimit()
    }

    private func trimEventsToLimit() {
        if events.count > limit {
            events.removeSubrange(limit..<events.count)
        }
    }

    private var agentsDirectoryURL: URL? {
        repositoryRoot?.appendingPathComponent(".agents", isDirectory: true)
    }

    private var timelineJSONLURL: URL? {
        agentsDirectoryURL?.appendingPathComponent("timeline.jsonl")
    }

    private var timelineMarkdownURL: URL? {
        agentsDirectoryURL?.appendingPathComponent("timeline.md")
    }

    private func persist(_ event: AgentTimelineEvent) {
        guard let agentsDirectoryURL, let timelineJSONLURL else { return }

        do {
            try FileManager.default.createDirectory(at: agentsDirectoryURL, withIntermediateDirectories: true)
            let encoder = Self.makeJSONEncoder()
            let data = try encoder.encode(event)
            let line = data + Data([0x0A])

            if FileManager.default.fileExists(atPath: timelineJSONLURL.path) {
                let handle = try FileHandle(forWritingTo: timelineJSONLURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: timelineJSONLURL, options: .atomic)
            }

            regenerateMarkdownSummary()
        } catch {
            return
        }
    }

    private func loadPersistedEvents(repositoryRoot: URL) -> [AgentTimelineEvent] {
        let url = repositoryRoot
            .appendingPathComponent(".agents", isDirectory: true)
            .appendingPathComponent("timeline.jsonl")
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let text = String(data: data, encoding: .utf8) ?? ""
        let decoder = Self.makeJSONDecoder()

        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? decoder.decode(AgentTimelineEvent.self, from: Data(String(line).utf8))
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func regenerateMarkdownSummary() {
        guard let agentsDirectoryURL, let timelineMarkdownURL else { return }

        do {
            try FileManager.default.createDirectory(at: agentsDirectoryURL, withIntermediateDirectories: true)
            try markdownSummary().write(to: timelineMarkdownURL, atomically: true, encoding: .utf8)
        } catch {
            return
        }
    }

    private func markdownSummary() -> String {
        let formatter = ISO8601DateFormatter()
        let updatedAt = formatter.string(from: now())
        let repositoryName = repositoryRoot?.lastPathComponent ?? "Unknown Repository"
        let recentEvents = Array(events.prefix(20))
        let commitEvents = events.compactMap(\.commit).prefix(5)
        let changedFiles = Array(
            Set(events.flatMap { event in
                event.changes?.files.map(\.path) ?? []
            })
        ).sorted()

        var lines: [String] = [
            "# Agent Timeline",
            "",
            "> Repository: \(repositoryName)",
            "> Updated: \(updatedAt)",
            "> Source: `.agents/timeline.jsonl`",
            "",
            "## 최근 작업 요약",
            ""
        ]

        if commitEvents.isEmpty && changedFiles.isEmpty {
            lines.append("- 아직 커밋 또는 변경 파일 요약이 없습니다.")
        } else {
            for commit in commitEvents {
                lines.append("- 커밋 `\(commit.shortHash)`: \(commit.subject)")
            }
            if !changedFiles.isEmpty {
                lines.append("- 최근 변경 파일 \(changedFiles.count)개가 Timeline에 기록되었습니다.")
            }
        }

        lines += [
            "",
            "## 최근 이벤트",
            "",
            "| 시간 | 종류 | 내용 |",
            "|---|---|---|"
        ]

        if recentEvents.isEmpty {
            lines.append("| - | - | 기록된 이벤트가 없습니다. |")
        } else {
            for event in recentEvents {
                let time = formatter.string(from: event.timestamp)
                lines.append("| \(time) | \(event.kind.displayName) | \(Self.escapeMarkdownTable(event.summaryDetail)) |")
            }
        }

        lines += [
            "",
            "## 변경 파일 하이라이트",
            ""
        ]

        if changedFiles.isEmpty {
            lines.append("- 아직 기록된 변경 파일이 없습니다.")
        } else {
            for path in changedFiles.prefix(20) {
                lines.append("- `\(path)`")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private nonisolated static func loadLatestCommitSnapshot(repositoryRoot: URL) throws -> AgentTimelineCommitSnapshot {
        let logOutput = try runGit(
            ["log", "-1", "--format=%H%x1f%h%x1f%s%x1f%an%x1f%cI"],
            repositoryRoot: repositoryRoot
        )
        let parts = logOutput.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard parts.count >= 5 else {
            throw AgentTimelineGitError.missingCommit
        }

        let files = try loadLatestCommitChangedFiles(repositoryRoot: repositoryRoot)
        let changes = AgentTimelineChanges(
            files: files,
            insertions: files.reduce(0) { $0 + $1.insertions },
            deletions: files.reduce(0) { $0 + $1.deletions }
        )
        let commit = AgentTimelineCommit(
            hash: String(parts[0]),
            shortHash: String(parts[1]),
            subject: String(parts[2]),
            author: String(parts[3]),
            committedAt: String(parts[4])
        )

        return AgentTimelineCommitSnapshot(commit: commit, changes: changes)
    }

    private nonisolated static func loadLatestCommitChangedFiles(repositoryRoot: URL) throws -> [AgentTimelineChangedFile] {
        let output = try runGit(["show", "--numstat", "--format=", "--no-renames", "HEAD"], repositoryRoot: repositoryRoot)
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AgentTimelineChangedFile? in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else { return nil }
                return AgentTimelineChangedFile(
                    path: String(parts[2]),
                    insertions: Int(parts[0]) ?? 0,
                    deletions: Int(parts[1]) ?? 0
                )
            }
    }

    private nonisolated static func runGit(_ arguments: [String], repositoryRoot: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot
        process.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "LANG": "C",
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AgentTimelineGitError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private nonisolated static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private nonisolated static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private nonisolated static func escapeMarkdownTable(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private enum AgentTimelineGitError: LocalizedError {
    case missingCommit
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCommit:
            return String(localized: "기록할 커밋을 찾을 수 없습니다.")
        case .commandFailed(let message):
            return message.isEmpty ? String(localized: "git 명령을 실행할 수 없습니다.") : message
        }
    }
}

private extension AgentTimelineEventKind {
    var displayName: String {
        switch self {
        case .terminal:
            return "터미널"
        case .markdown:
            return "마크다운"
        case .gitDiff:
            return "Git Diff"
        case .commit:
            return "커밋"
        }
    }
}

private extension AgentTimelineEvent {
    var summaryDetail: String {
        if let commit {
            return "\(detail) (`\(commit.shortHash)` · +\(changes?.insertions ?? 0) -\(changes?.deletions ?? 0))"
        }
        return detail
    }
}
