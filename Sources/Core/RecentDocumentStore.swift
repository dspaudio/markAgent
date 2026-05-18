import Foundation

struct RecentDocument: Codable, Equatable, Identifiable {
    var id: String { path }

    let path: String
    let title: String
    let directory: String
    let lastOpenedAt: Date
}

@Observable
@MainActor
final class RecentDocumentStore {
    private let defaults: UserDefaults
    private let storageKey = "recentDocuments"
    private let limit = 12

    var documents: [RecentDocument] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func record(url: URL) {
        let document = RecentDocument(
            path: url.path,
            title: url.deletingPathExtension().lastPathComponent,
            directory: url.deletingLastPathComponent().path,
            lastOpenedAt: Date()
        )

        documents.removeAll { $0.path == document.path }
        documents.insert(document, at: 0)
        if documents.count > limit {
            documents = Array(documents.prefix(limit))
        }
        save()
    }

    func remove(_ document: RecentDocument) {
        documents.removeAll { $0.path == document.path }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) else {
            documents = []
            return
        }

        documents = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
