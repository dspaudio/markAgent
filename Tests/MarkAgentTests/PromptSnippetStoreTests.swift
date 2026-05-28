import XCTest
@testable import ma

final class PromptSnippetStoreTests: XCTestCase {
    @MainActor
    func testAddReloadPreservesBodyExactly() {
        let suiteName = "PromptSnippetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let body = "  first line\nsecond line  "
        let store = PromptSnippetStore(defaults: defaults)

        let snippet = store.add(body: body)
        let reloaded = PromptSnippetStore(defaults: defaults)

        XCTAssertNotNil(snippet)
        XCTAssertEqual(reloaded.snippets.count, 1)
        XCTAssertEqual(reloaded.snippets.first?.body, body)
    }

    @MainActor
    func testEditUpdatesBodyAndMovesSnippetToTop() {
        let suiteName = "PromptSnippetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 300),
        ]
        let store = PromptSnippetStore(defaults: defaults) { dates.removeFirst() }

        let first = store.add(body: "first")!
        let second = store.add(body: "second")!
        let updated = store.update(first, body: "first edited")

        XCTAssertNotNil(updated)
        XCTAssertEqual(store.snippets.map(\.body), ["first edited", "second"])
        XCTAssertEqual(store.snippets.first?.id, first.id)
        XCTAssertEqual(store.snippets.last?.id, second.id)
    }

    @MainActor
    func testDeleteRemovesSnippetAfterReload() {
        let suiteName = "PromptSnippetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PromptSnippetStore(defaults: defaults)
        let snippet = store.add(body: "delete me")!

        store.delete(snippet)
        let reloaded = PromptSnippetStore(defaults: defaults)

        XCTAssertTrue(reloaded.snippets.isEmpty)
    }

    @MainActor
    func testRejectsEmptyBody() {
        let suiteName = "PromptSnippetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PromptSnippetStore(defaults: defaults)

        XCTAssertNil(store.add(body: "  \n\t  "))
        XCTAssertTrue(store.snippets.isEmpty)
    }

    @MainActor
    func testRejectsEmptyBodyOnUpdate() {
        let suiteName = "PromptSnippetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PromptSnippetStore(defaults: defaults)
        let snippet = store.add(body: "keep me")!

        XCTAssertNil(store.update(snippet, body: " \n "))
        XCTAssertEqual(store.snippets.map(\.body), ["keep me"])
    }
}
