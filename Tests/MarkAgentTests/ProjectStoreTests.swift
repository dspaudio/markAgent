import Foundation
import XCTest
@testable import ma

final class ProjectStoreTests: XCTestCase {
    @MainActor
    func testAddPersistsTrimmedNameAndCanonicalDirectoryURL() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let realDirectory = directory.appendingPathComponent("workspace", isDirectory: true)
        let symlink = directory.appendingPathComponent("workspace-link", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realDirectory)
        let nonCanonicalURL = symlink
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(symlink.lastPathComponent, isDirectory: true)
        let expectedURL = realDirectory.resolvingSymlinksInPath().standardizedFileURL

        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "  Workspace  ", directoryURL: nonCanonicalURL))
        let reloaded = ProjectStore(defaults: defaults)

        XCTAssertEqual(project.name, "Workspace")
        XCTAssertEqual(project.directoryURL, expectedURL)
        XCTAssertEqual(reloaded.projects, [project])
    }

    @MainActor
    func testUpdatePreservesIdentityAndOrderAndPersists() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let firstDirectory = try createDirectory(named: "first", in: directory)
        let secondDirectory = try createDirectory(named: "second", in: directory)
        let updatedDirectory = try createDirectory(named: "updated", in: directory)
        let store = ProjectStore(defaults: defaults)
        let first = try XCTUnwrap(store.add(name: "First", directoryURL: firstDirectory))
        let second = try XCTUnwrap(store.add(name: "Second", directoryURL: secondDirectory))

        let updated = try XCTUnwrap(store.update(first, name: "  Renamed  ", directoryURL: updatedDirectory))
        let reloaded = ProjectStore(defaults: defaults)

        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(store.projects.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.projects.map(\.name), ["Renamed", "Second"])
        XCTAssertEqual(reloaded.projects, store.projects)
    }

    @MainActor
    func testDeletePersists() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: directory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))

        store.delete(project)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(ProjectStore(defaults: defaults).projects.isEmpty)
    }

    @MainActor
    func testRejectedAddsAndUpdatesLeaveProjectsAndPersistedDataUnchanged() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let validDirectory = try createDirectory(named: "valid", in: directory)
        let missingDirectory = directory.appendingPathComponent("missing", isDirectory: true)
        let regularFile = directory.appendingPathComponent("file")
        let remoteDirectory = URL(string: "https://example.com/workspace")!
        try Data().write(to: regularFile)
        let store = ProjectStore(defaults: defaults)
        let existing = try XCTUnwrap(store.add(name: "Existing", directoryURL: validDirectory))
        let expectedProjects = store.projects
        let expectedData = try XCTUnwrap(persistedData(in: defaults))

        XCTAssertNil(store.add(name: " \n\t ", directoryURL: validDirectory))
        XCTAssertNil(store.add(name: "URL", directoryURL: remoteDirectory))
        XCTAssertNil(store.add(name: "Missing", directoryURL: missingDirectory))
        XCTAssertNil(store.add(name: "File", directoryURL: regularFile))
        XCTAssertNil(store.update(existing, name: " \n\t ", directoryURL: validDirectory))
        XCTAssertNil(store.update(existing, name: "URL", directoryURL: remoteDirectory))
        XCTAssertNil(store.update(existing, name: "Missing", directoryURL: missingDirectory))
        XCTAssertNil(store.update(existing, name: "File", directoryURL: regularFile))

        XCTAssertEqual(store.projects, expectedProjects)
        XCTAssertEqual(store.projects.map(\.id), [existing.id])
        XCTAssertEqual(persistedData(in: defaults), expectedData)
    }

    @MainActor
    func testDuplicateCanonicalPathIsRejectedOnAddAndUpdateWithoutMutation() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let firstDirectory = try createDirectory(named: "first", in: directory)
        let duplicateSymlink = directory.appendingPathComponent("first-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: duplicateSymlink, withDestinationURL: firstDirectory)
        let secondDirectory = try createDirectory(named: "second", in: directory)
        let store = ProjectStore(defaults: defaults)
        let first = try XCTUnwrap(store.add(name: "First", directoryURL: firstDirectory))
        let second = try XCTUnwrap(store.add(name: "Second", directoryURL: secondDirectory))
        let expectedProjects = store.projects
        let expectedData = try XCTUnwrap(persistedData(in: defaults))

        XCTAssertNil(store.add(name: "Duplicate", directoryURL: duplicateSymlink))
        XCTAssertNil(store.update(second, name: "Duplicate", directoryURL: duplicateSymlink))

        XCTAssertEqual(store.projects, expectedProjects)
        XCTAssertEqual(store.projects.map(\.id), [first.id, second.id])
        XCTAssertEqual(persistedData(in: defaults), expectedData)
    }

    @MainActor
    func testStaleProjectResolvesCurrentRecordAndUnavailableDirectoryReturnsNil() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let originalDirectory = try createDirectory(named: "original", in: directory)
        let currentDirectory = try createDirectory(named: "current", in: directory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: originalDirectory))
        let staleProject = project
        _ = try XCTUnwrap(store.update(project, name: "Renamed", directoryURL: currentDirectory))

        XCTAssertEqual(store.validatedDirectoryURL(for: staleProject), currentDirectory.standardizedFileURL)

        try FileManager.default.removeItem(at: currentDirectory)

        XCTAssertNil(store.validatedDirectoryURL(for: staleProject))
    }

    @MainActor
    func testUnavailableRecordsSurviveReloadUntilExplicitDeletion() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let projectDirectory = try createDirectory(named: "workspace", in: directory)
        let store = ProjectStore(defaults: defaults)
        let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: projectDirectory))
        try FileManager.default.removeItem(at: projectDirectory)

        let reloaded = ProjectStore(defaults: defaults)
        let unavailableProject = try XCTUnwrap(reloaded.projects.first)

        XCTAssertEqual(unavailableProject.id, project.id)
        XCTAssertNil(reloaded.validatedDirectoryURL(for: unavailableProject))

        reloaded.delete(unavailableProject)

        XCTAssertTrue(ProjectStore(defaults: defaults).projects.isEmpty)
    }

    @MainActor
    func testMalformedPayloadLoadsEmptyWithoutOverwritingRawDefaultsData() {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let malformedData = Data([0x00, 0xFF, 0x01, 0x7F])
        defaults.set(malformedData, forKey: projectsDefaultsKey)

        let store = ProjectStore(defaults: defaults)

        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertEqual(persistedData(in: defaults), malformedData)
    }

    @MainActor
    func testMoveProjectsMovesSingleProjectToEndAndPersistsOrder() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ProjectStore(defaults: defaults)
        let projects = try addProjects(named: ["A", "B", "C"], to: store, in: directory)

        XCTAssertTrue(store.moveProjects(fromOffsets: IndexSet([0]), toOffset: 3))

        XCTAssertEqual(store.projects.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(store.projects.map(\.id), [projects[1].id, projects[2].id, projects[0].id])
        XCTAssertEqual(ProjectStore(defaults: defaults).projects.map(\.id), [projects[1].id, projects[2].id, projects[0].id])
    }

    @MainActor
    func testMoveProjectsMovesMultipleProjectsInRelativeOrderAndPersists() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ProjectStore(defaults: defaults)
        let projects = try addProjects(named: ["A", "B", "C", "D"], to: store, in: directory)

        XCTAssertTrue(store.moveProjects(fromOffsets: IndexSet([1, 2]), toOffset: 0))

        XCTAssertEqual(store.projects.map(\.name), ["B", "C", "A", "D"])
        XCTAssertEqual(store.projects.map(\.id), [projects[1].id, projects[2].id, projects[0].id, projects[3].id])
        XCTAssertEqual(ProjectStore(defaults: defaults).projects.map(\.id), [projects[1].id, projects[2].id, projects[0].id, projects[3].id])
    }

    @MainActor
    func testMoveProjectsRejectsInvalidRequestsWithoutMutatingProjectsOrPersistedData() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ProjectStore(defaults: defaults)
        let projects = try addProjects(named: ["A", "B", "C"], to: store, in: directory)
        let expectedProjects = store.projects
        let expectedData = try XCTUnwrap(persistedData(in: defaults))

        XCTAssertFalse(store.moveProjects(fromOffsets: IndexSet(), toOffset: 0))
        XCTAssertEqual(store.projects, expectedProjects)
        XCTAssertEqual(persistedData(in: defaults), expectedData)

        XCTAssertFalse(store.moveProjects(fromOffsets: IndexSet([3]), toOffset: 0))
        XCTAssertEqual(store.projects, expectedProjects)
        XCTAssertEqual(persistedData(in: defaults), expectedData)

        XCTAssertFalse(store.moveProjects(fromOffsets: IndexSet([0]), toOffset: 4))
        XCTAssertEqual(store.projects, expectedProjects)
        XCTAssertEqual(store.projects.map(\.id), [projects[0].id, projects[1].id, projects[2].id])
        XCTAssertEqual(persistedData(in: defaults), expectedData)
    }

    @MainActor
    func testMoveProjectsNoOpDoesNotRewritePersistedData() throws {
        let suiteName = "ProjectStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = try makeTemporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ProjectStore(defaults: defaults)
        let projects = try addProjects(named: ["A", "B"], to: store, in: directory)
        let expectedData = try XCTUnwrap(persistedData(in: defaults))

        XCTAssertFalse(store.moveProjects(fromOffsets: IndexSet([0]), toOffset: 0))

        XCTAssertEqual(store.projects.map(\.id), [projects[0].id, projects[1].id])
        XCTAssertEqual(persistedData(in: defaults), expectedData)
    }

    private let projectsDefaultsKey = "projects"

    private func persistedData(in defaults: UserDefaults) -> Data? {
        defaults.data(forKey: projectsDefaultsKey)
    }

    @MainActor
    private func addProjects(named names: [String], to store: ProjectStore, in parent: URL) throws -> [Project] {
        try names.map { name in
            let directory = try createDirectory(named: name, in: parent)
            return try XCTUnwrap(store.add(name: name, directoryURL: directory))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
