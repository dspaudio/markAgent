import Foundation

enum RightSidebarTab: String, CaseIterable, Identifiable {
    case gitChanges
    case timeline
    case snippets

    var id: String { rawValue }
}
