import Foundation
import SwiftUI
import XCTest
@testable import ma

final class ProjectSidebarControllerTests: XCTestCase {
    func testWorkspaceLocalizationKeysExistInKoreanAndEnglish() throws {
        let keys = [
            "미분류",
            "확인",
            "폴더는 삭제되지 않으며 열려 있는 탭은 미분류 workspace로 이동합니다.",
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let korean = try String(
            contentsOf: root.appending(path: "Sources/App/Resources/ko.lproj/Localizable.strings"),
            encoding: .utf8
        )
        let english = try String(
            contentsOf: root.appending(path: "Sources/App/Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )

        for key in keys {
            XCTAssertTrue(korean.contains("\"\(key)\" ="), "Missing Korean key \(key)")
            XCTAssertTrue(english.contains("\"\(key)\" ="), "Missing English key \(key)")
        }
    }

    func testWorkspaceSelectionAccessibilityExposesSelectedTrait() {
        XCTAssertTrue(
            ProjectWorkspaceAccessibility.traits(isSelected: true).contains(.isSelected)
        )
        XCTAssertFalse(
            ProjectWorkspaceAccessibility.traits(isSelected: false).contains(.isSelected)
        )
    }

    @MainActor
    func testSelectDeliversCallbackExactlyOnceWithoutMutatingStore() throws {
        try withIsolatedStore { store, root, defaults in
            let directory = try createDirectory(named: "workspace", in: root)
            let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: directory))
            let expectedProjects = store.projects
            let expectedPersistedData = defaults.data(forKey: projectsDefaultsKey)
            var selectedProjects: [Project] = []
            let controller = ProjectSidebarController(projectStore: store) { project in
                selectedProjects.append(project)
            }

            controller.select(project)

            XCTAssertEqual(selectedProjects, [project])
            XCTAssertEqual(store.projects, expectedProjects)
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)
        }
    }

    @MainActor
    func testSelectUnscopedDeliversCallbackExactlyOnce() throws {
        try withIsolatedStore { store, _, _ in
            var selectionCount = 0
            let controller = ProjectSidebarController(
                projectStore: store,
                onSelectProject: { _ in },
                onSelectUnscoped: {
                    selectionCount += 1
                }
            )

            controller.selectUnscoped()

            XCTAssertEqual(selectionCount, 1)
        }
    }

    @MainActor
    func testBeginAddDefaultsNameFromDirectory() throws {
        try withIsolatedStore { store, root, _ in
            let directory = try createDirectory(named: "My Workspace", in: root)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.beginAdd(directoryURL: directory)

            XCTAssertEqual(controller.editor?.mode, .add)
            XCTAssertEqual(controller.editor?.name, "My Workspace")
            XCTAssertEqual(controller.editor?.directoryURL, directory.standardizedFileURL)
            XCTAssertNil(controller.editor?.failure)
        }
    }

    @MainActor
    func testSaveEditorAddsProjectClearsEditorAndPersists() throws {
        try withIsolatedStore { store, root, defaults in
            let directory = try createDirectory(named: "workspace", in: root)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.beginAdd(directoryURL: directory)
            controller.setEditorName("Workspace")
            controller.saveEditor()

            let project = try XCTUnwrap(store.projects.first)
            XCTAssertNil(controller.editor)
            XCTAssertEqual(project.name, "Workspace")
            XCTAssertEqual(project.directoryURL, directory.standardizedFileURL)
            XCTAssertEqual(ProjectStore(defaults: defaults).projects, [project])
        }
    }

    @MainActor
    func testSaveEditorUpdatesProjectWithoutChangingIdentityOrOrderAndPersists() throws {
        try withIsolatedStore { store, root, defaults in
            let firstDirectory = try createDirectory(named: "first", in: root)
            let secondDirectory = try createDirectory(named: "second", in: root)
            let updatedDirectory = try createDirectory(named: "updated", in: root)
            let first = try XCTUnwrap(store.add(name: "First", directoryURL: firstDirectory))
            let second = try XCTUnwrap(store.add(name: "Second", directoryURL: secondDirectory))
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.beginEdit(first)
            controller.setEditorName("Renamed")
            controller.setEditorDirectory(updatedDirectory)
            controller.saveEditor()

            XCTAssertNil(controller.editor)
            XCTAssertEqual(store.projects.map(\.id), [first.id, second.id])
            XCTAssertEqual(store.projects.map(\.name), ["Renamed", "Second"])
            XCTAssertEqual(store.projects[0].directoryURL, updatedDirectory.standardizedFileURL)
            XCTAssertEqual(ProjectStore(defaults: defaults).projects, store.projects)
        }
    }

    @MainActor
    func testSuccessfulEditEmitsUpdatedProjectExactlyOnce() throws {
        try withIsolatedStore { store, root, _ in
            let originalDirectory = try createDirectory(named: "original", in: root)
            let updatedDirectory = try createDirectory(named: "updated", in: root)
            let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: originalDirectory))
            var updatedProjects: [Project] = []
            let controller = ProjectSidebarController(
                projectStore: store,
                onSelectProject: { _ in },
                onProjectUpdated: { updatedProjects.append($0) }
            )

            controller.beginEdit(project)
            controller.setEditorDirectory(updatedDirectory)
            XCTAssertTrue(controller.saveEditor())

            XCTAssertEqual(updatedProjects, store.projects)
        }
    }

    @MainActor
    func testRejectedAddKeepsEditorOpenAndSetsStoreRejectedFailure() throws {
        try withIsolatedStore { store, root, defaults in
            let directory = try createDirectory(named: "workspace", in: root)
            let existing = try XCTUnwrap(store.add(name: "Existing", directoryURL: directory))
            let expectedPersistedData = defaults.data(forKey: projectsDefaultsKey)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.beginAdd(directoryURL: directory)
            controller.saveEditor()

            XCTAssertEqual(controller.editor?.mode, .add)
            XCTAssertEqual(controller.editor?.directoryURL, directory.standardizedFileURL)
            XCTAssertEqual(controller.editor?.failure, .storeRejected)
            XCTAssertEqual(store.projects, [existing])
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)
        }
    }

    @MainActor
    func testRejectedEditKeepsEditorOpenAndSetsStoreRejectedFailure() throws {
        try withIsolatedStore { store, root, defaults in
            let firstDirectory = try createDirectory(named: "first", in: root)
            let secondDirectory = try createDirectory(named: "second", in: root)
            let first = try XCTUnwrap(store.add(name: "First", directoryURL: firstDirectory))
            let second = try XCTUnwrap(store.add(name: "Second", directoryURL: secondDirectory))
            let expectedProjects = store.projects
            let expectedPersistedData = defaults.data(forKey: projectsDefaultsKey)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.beginEdit(second)
            controller.setEditorDirectory(firstDirectory)
            controller.saveEditor()

            XCTAssertEqual(controller.editor?.mode, .edit(second))
            XCTAssertEqual(controller.editor?.directoryURL, firstDirectory.standardizedFileURL)
            XCTAssertEqual(controller.editor?.failure, .storeRejected)
            XCTAssertEqual(store.projects, expectedProjects)
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)
            XCTAssertEqual(store.projects.map(\.id), [first.id, second.id])
        }
    }

    @MainActor
    func testDeleteRequestDoesNotMutateStoreAndCancelPreservesData() throws {
        try withIsolatedStore { store, root, defaults in
            let directory = try createDirectory(named: "workspace", in: root)
            let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: directory))
            let expectedPersistedData = defaults.data(forKey: projectsDefaultsKey)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.requestDelete(project)

            XCTAssertEqual(controller.deleteRequest, project)
            XCTAssertEqual(store.projects, [project])
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)

            controller.cancelDelete()

            XCTAssertNil(controller.deleteRequest)
            XCTAssertEqual(store.projects, [project])
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)
        }
    }

    @MainActor
    func testConfirmDeleteClearsRequestAndPersistsDeletion() throws {
        try withIsolatedStore { store, root, defaults in
            let directory = try createDirectory(named: "workspace", in: root)
            let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: directory))
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.requestDelete(project)
            controller.confirmDelete()

            XCTAssertNil(controller.deleteRequest)
            XCTAssertTrue(store.projects.isEmpty)
            XCTAssertTrue(ProjectStore(defaults: defaults).projects.isEmpty)
        }
    }

    @MainActor
    func testConfirmDeleteEmitsDeletedProjectAfterStoreMutation() throws {
        try withIsolatedStore { store, root, _ in
            let directory = try createDirectory(named: "workspace", in: root)
            let project = try XCTUnwrap(store.add(name: "Workspace", directoryURL: directory))
            var deletionSnapshots: [([Project], Project)] = []
            let controller = ProjectSidebarController(
                projectStore: store,
                onSelectProject: { _ in },
                onProjectDeleted: { deletedProject in
                    deletionSnapshots.append((store.projects, deletedProject))
                }
            )

            controller.requestDelete(project)
            controller.confirmDelete()

            XCTAssertEqual(deletionSnapshots.count, 1)
            XCTAssertTrue(deletionSnapshots[0].0.isEmpty)
            XCTAssertEqual(deletionSnapshots[0].1, project)
        }
    }

    @MainActor
    func testMoveProjectsReordersABCAndPersists() throws {
        try withIsolatedStore { store, root, defaults in
            let aDirectory = try createDirectory(named: "a", in: root)
            let bDirectory = try createDirectory(named: "b", in: root)
            let cDirectory = try createDirectory(named: "c", in: root)
            let a = try XCTUnwrap(store.add(name: "A", directoryURL: aDirectory))
            let b = try XCTUnwrap(store.add(name: "B", directoryURL: bDirectory))
            let c = try XCTUnwrap(store.add(name: "C", directoryURL: cDirectory))
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            XCTAssertTrue(controller.moveProjects(fromOffsets: IndexSet(integer: 0), toOffset: 3))

            XCTAssertEqual(store.projects, [b, c, a])
            XCTAssertEqual(ProjectStore(defaults: defaults).projects, [b, c, a])
        }
    }

    @MainActor
    func testMoveProjectsRejectsInvalidAndNoOpMovesWithoutMutation() throws {
        try withIsolatedStore { store, root, defaults in
            let aDirectory = try createDirectory(named: "a", in: root)
            let bDirectory = try createDirectory(named: "b", in: root)
            let cDirectory = try createDirectory(named: "c", in: root)
            let a = try XCTUnwrap(store.add(name: "A", directoryURL: aDirectory))
            let b = try XCTUnwrap(store.add(name: "B", directoryURL: bDirectory))
            let c = try XCTUnwrap(store.add(name: "C", directoryURL: cDirectory))
            let expectedProjects = [a, b, c]
            let expectedPersistedData = defaults.data(forKey: projectsDefaultsKey)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            XCTAssertFalse(controller.moveProjects(fromOffsets: [], toOffset: 0))
            XCTAssertFalse(controller.moveProjects(fromOffsets: IndexSet(integer: 3), toOffset: 0))
            XCTAssertFalse(controller.moveProjects(fromOffsets: IndexSet(integer: 0), toOffset: 1))

            XCTAssertEqual(store.projects, expectedProjects)
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)
        }
    }

    @MainActor
    func testCancelEditorClearsDraftWithoutMutatingStore() throws {
        try withIsolatedStore { store, root, defaults in
            let directory = try createDirectory(named: "workspace", in: root)
            let expectedPersistedData = defaults.data(forKey: projectsDefaultsKey)
            let controller = ProjectSidebarController(projectStore: store, onSelectProject: { _ in })

            controller.beginAdd(directoryURL: directory)
            controller.cancelEditor()

            XCTAssertNil(controller.editor)
            XCTAssertTrue(store.projects.isEmpty)
            XCTAssertEqual(defaults.data(forKey: projectsDefaultsKey), expectedPersistedData)
        }
    }

    private let projectsDefaultsKey = "projects"

    @MainActor
    private func withIsolatedStore(
        _ body: (ProjectStore, URL, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "ProjectSidebarControllerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectSidebarControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        try body(ProjectStore(defaults: defaults), directory, defaults)
    }

    private func createDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
