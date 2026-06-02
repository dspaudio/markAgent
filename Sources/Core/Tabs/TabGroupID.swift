import Foundation

struct TabGroupID: Hashable, Identifiable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

