import Foundation

@MainActor
@Observable
final class SettingsTab: MarkAgentTab {
    let id: UUID
    let kind: TabKind = .settings
    let title = "Settings"
    let isDirty = false
    let isClosable = true
    let groupID: TabGroupID? = nil

    init(id: UUID = UUID()) {
        self.id = id
    }

    func prepareForClose() async -> Bool {
        true
    }
}
