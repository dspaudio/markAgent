import Foundation

struct PromptSnippet: Codable, Equatable, Identifiable {
    let id: UUID
    let body: String
    let createdAt: Date
    let updatedAt: Date
}

@Observable
@MainActor
final class PromptSnippetStore {
    private let defaults: UserDefaults
    private let storageKey = "promptSnippets"
    private let now: () -> Date

    private(set) var snippets: [PromptSnippet] = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        load()
    }

    @discardableResult
    func add(body: String) -> PromptSnippet? {
        guard isValidBody(body) else { return nil }

        let date = now()
        let snippet = PromptSnippet(
            id: UUID(),
            body: body,
            createdAt: date,
            updatedAt: date
        )

        snippets.append(snippet)
        sortLatestUpdatedFirst()
        save()
        return snippet
    }

    @discardableResult
    func update(_ snippet: PromptSnippet, body: String) -> PromptSnippet? {
        guard isValidBody(body) else { return nil }
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return nil }

        let updated = PromptSnippet(
            id: snippet.id,
            body: body,
            createdAt: snippets[index].createdAt,
            updatedAt: now()
        )

        snippets[index] = updated
        sortLatestUpdatedFirst()
        save()
        return updated
    }

    func delete(_ snippet: PromptSnippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    private func isValidBody(_ body: String) -> Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PromptSnippet].self, from: data) else {
            snippets = []
            return
        }

        snippets = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func sortLatestUpdatedFirst() {
        snippets.sort { $0.updatedAt > $1.updatedAt }
    }
}
