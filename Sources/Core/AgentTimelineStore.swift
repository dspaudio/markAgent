import Foundation

enum AgentTimelineEventKind: String, Equatable {
    case terminal
    case markdown
    case gitDiff
}

struct AgentTimelineEvent: Identifiable, Equatable {
    let id: UUID
    let kind: AgentTimelineEventKind
    let title: String
    let detail: String
    let timestamp: Date
}

enum AgentTimelineAction {
    case terminalCreated(directory: URL)
    case markdownOpened(url: URL)
    case gitDiffFocused(relativePath: String)
}

@MainActor
@Observable
final class AgentTimelineStore {
    private(set) var events: [AgentTimelineEvent] = []

    private let limit: Int
    private let now: () -> Date

    init(limit: Int = 100, now: @escaping @autoclosure () -> Date = Date()) {
        self.limit = max(1, limit)
        self.now = now
    }

    func record(_ action: AgentTimelineAction) {
        events.insert(event(for: action), at: 0)
        if events.count > limit {
            events.removeSubrange(limit..<events.count)
        }
    }

    private func event(for action: AgentTimelineAction) -> AgentTimelineEvent {
        switch action {
        case .terminalCreated(let directory):
            return AgentTimelineEvent(
                id: UUID(),
                kind: .terminal,
                title: "터미널 탭",
                detail: directory.path,
                timestamp: now()
            )
        case .markdownOpened(let url):
            return AgentTimelineEvent(
                id: UUID(),
                kind: .markdown,
                title: "마크다운 열림",
                detail: url.lastPathComponent,
                timestamp: now()
            )
        case .gitDiffFocused(let relativePath):
            return AgentTimelineEvent(
                id: UUID(),
                kind: .gitDiff,
                title: "Diff 포커스",
                detail: relativePath,
                timestamp: now()
            )
        }
    }
}
