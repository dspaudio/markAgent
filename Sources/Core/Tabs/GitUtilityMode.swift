import Foundation

enum GitUtilityMode: String, CaseIterable, Identifiable {
    case history
    case changes

    var id: String { rawValue }
}
