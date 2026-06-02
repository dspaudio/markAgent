import Foundation

@MainActor
protocol MarkAgentTab: AnyObject, Identifiable {
    var id: UUID { get }
    var kind: TabKind { get }
    var title: String { get }
    var isDirty: Bool { get }
    var isClosable: Bool { get }
    var groupID: TabGroupID? { get }

    func prepareForClose() async -> Bool
}
