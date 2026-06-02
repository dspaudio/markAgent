import Foundation

@MainActor
@Observable
final class TerminalTab: MarkAgentTab {
    let id: UUID
    let kind: TabKind = .terminal
    let workingDirectory: URL
    let state: TerminalTabState
    let groupState: TabGroupState
    var title: String { state.title }
    var isDirty: Bool { false }
    var isClosable: Bool { true }
    var groupID: TabGroupID? { groupState.id }

    init(id: UUID = UUID(), workingDirectory: URL, state: TerminalTabState? = nil, groupState: TabGroupState? = nil) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.groupState = groupState ?? TabGroupState(workingDirectory: workingDirectory)
        self.state = state ?? TerminalTabState(id: id, workingDirectory: workingDirectory)
    }

    func prepareForClose() async -> Bool {
        state.close()
        return true
    }
}
