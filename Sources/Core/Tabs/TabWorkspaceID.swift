import Foundation

enum TabWorkspaceID: Hashable, Identifiable, Sendable {
    case unscoped
    case project(Project.ID)

    var id: Self { self }
}
