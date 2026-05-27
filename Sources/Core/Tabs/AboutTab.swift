import Foundation

@MainActor
@Observable
final class AboutTab: MarkAgentTab {
    let id: UUID
    let kind: TabKind = .about
    let title = "About"
    let isDirty = false
    let isClosable = true

    init(id: UUID = UUID()) {
        self.id = id
    }

    func prepareForClose() async -> Bool {
        true
    }
}
