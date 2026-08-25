import Foundation
import Observation

enum ProjectEditorMode: Equatable {
    case add
    case edit(Project)
}

enum ProjectEditorFailure: Equatable {
    case storeRejected
}

struct ProjectEditorState: Equatable, Identifiable {
    let id: UUID
    let mode: ProjectEditorMode
    var name: String
    var directoryURL: URL
    var failure: ProjectEditorFailure?

    init(
        id: UUID = UUID(),
        mode: ProjectEditorMode,
        name: String,
        directoryURL: URL,
        failure: ProjectEditorFailure? = nil
    ) {
        self.id = id
        self.mode = mode
        self.name = name
        self.directoryURL = directoryURL.standardizedFileURL
        self.failure = failure
    }
}

@Observable
@MainActor
final class ProjectSidebarController {
    private let projectStore: ProjectStore
    private let onSelectProject: (Project) -> Void
    private let onSelectUnscoped: () -> Void
    private let onProjectUpdated: (Project) -> Void
    private let onProjectDeleted: (Project) -> Void

    var editor: ProjectEditorState?
    var deleteRequest: Project?

    init(
        projectStore: ProjectStore,
        onSelectProject: @escaping (Project) -> Void,
        onSelectUnscoped: @escaping () -> Void = {},
        onProjectUpdated: @escaping (Project) -> Void = { _ in },
        onProjectDeleted: @escaping (Project) -> Void = { _ in }
    ) {
        self.projectStore = projectStore
        self.onSelectProject = onSelectProject
        self.onSelectUnscoped = onSelectUnscoped
        self.onProjectUpdated = onProjectUpdated
        self.onProjectDeleted = onProjectDeleted
    }

    func select(_ project: Project) {
        onSelectProject(project)
    }

    func selectUnscoped() {
        onSelectUnscoped()
    }

    func beginAdd(directoryURL: URL) {
        editor = ProjectEditorState(
            mode: .add,
            name: directoryURL.lastPathComponent,
            directoryURL: directoryURL
        )
    }

    func beginEdit(_ project: Project) {
        editor = ProjectEditorState(
            mode: .edit(project),
            name: project.name,
            directoryURL: project.directoryURL
        )
    }

    func setEditorName(_ name: String) {
        editor?.name = name
        editor?.failure = nil
    }

    func setEditorDirectory(_ directoryURL: URL) {
        editor?.directoryURL = directoryURL.standardizedFileURL
        editor?.failure = nil
    }

    @discardableResult
    func saveEditor() -> Bool {
        guard var editor else { return false }

        let savedProject: Project?
        switch editor.mode {
        case .add:
            savedProject = projectStore.add(
                name: editor.name,
                directoryURL: editor.directoryURL
            )
        case .edit(let project):
            savedProject = projectStore.update(
                project,
                name: editor.name,
                directoryURL: editor.directoryURL
            )
        }

        guard let savedProject else {
            editor.failure = .storeRejected
            self.editor = editor
            return false
        }

        if case .edit = editor.mode {
            onProjectUpdated(savedProject)
        }
        self.editor = nil
        return true
    }

    func cancelEditor() {
        editor = nil
    }

    func dismissEditorFailure() {
        editor?.failure = nil
    }

    @discardableResult
    func moveProjects(fromOffsets: IndexSet, toOffset: Int) -> Bool {
        projectStore.moveProjects(
            fromOffsets: fromOffsets,
            toOffset: toOffset
        )
    }

    func requestDelete(_ project: Project) {
        deleteRequest = project
    }

    func cancelDelete() {
        deleteRequest = nil
    }

    func confirmDelete() {
        guard let deleteRequest else { return }
        projectStore.delete(deleteRequest)
        self.deleteRequest = nil
        onProjectDeleted(deleteRequest)
    }
}
