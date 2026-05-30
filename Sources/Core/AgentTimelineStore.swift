import Foundation

enum AgentTimelineEventKind: String, Codable, Equatable {
    case terminal = "terminal_created"
    case markdown = "markdown_opened"
    case gitDiff = "git_diff_focused"
    case changeSummary = "change_summary"
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

struct AgentTimelineEvent: Identifiable, Codable, Equatable {
    let version: Int
    let id: UUID
    let kind: AgentTimelineEventKind
    let title: String
    let detail: String
    let timestamp: Date
    let source: String
    let repositoryRoot: String?
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
        self.changes = changes
    }
}

enum AgentTimelineAction {
    case terminalCreated(directory: URL)
    case markdownOpened(url: URL)
    case gitDiffFocused(relativePath: String)
    case changeSummary(title: String, detail: String, changes: AgentTimelineChanges?)
}

@MainActor
@Observable
final class AgentTimelineStore {
    private(set) var events: [AgentTimelineEvent] = []

    private let limit: Int
    private let now: () -> Date
    private var repositoryRoot: URL?

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
    }

    func record(_ action: AgentTimelineAction) {
        let event = event(for: action)
        events.insert(event, at: 0)
        trimEventsToLimit()
        if event.shouldPersistToSharedTimeline {
            persist(event)
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
        case .changeSummary(let title, let detail, let changes):
            return AgentTimelineEvent(
                kind: .changeSummary,
                title: title,
                detail: detail,
                timestamp: now(),
                repositoryRoot: repositoryRootPath,
                changes: changes
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
        let sharedEvents = events.filter(\.shouldPersistToSharedTimeline)
        let recentEvents = Array(sharedEvents.prefix(20))
        let changedFiles = Array(
            Set(sharedEvents.flatMap { event in
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

        if recentEvents.isEmpty && changedFiles.isEmpty {
            lines.append("- 아직 공유된 작업 요약이 없습니다.")
        } else {
            for event in recentEvents.prefix(5) {
                lines.append("- \(event.detail)")
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
            lines.append("| - | - | 기록된 공유 이벤트가 없습니다. |")
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

private extension AgentTimelineEventKind {
    var displayName: String {
        switch self {
        case .terminal:
            return "터미널"
        case .markdown:
            return "마크다운"
        case .gitDiff:
            return "Git Diff"
        case .changeSummary:
            return "작업 요약"
        }
    }
}

private extension AgentTimelineEvent {
    var shouldPersistToSharedTimeline: Bool {
        switch kind {
        case .changeSummary:
            return true
        case .terminal, .markdown, .gitDiff:
            return false
        }
    }

    var summaryDetail: String {
        if let changes {
            return "\(detail) (+\(changes.insertions) -\(changes.deletions))"
        }
        return detail
    }
}
