import Foundation
import Observation

struct Project: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let path: String

    var directoryURL: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

@Observable
@MainActor
final class ProjectStore {
    private let defaults: UserDefaults
    private let storageKey = "projects"

    private(set) var projects: [Project] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func add(name: String, directoryURL: URL) -> Project? {
        guard let name = normalizedName(name),
              let directoryURL = canonicalDirectoryURL(for: directoryURL),
              !projects.contains(where: { $0.path == directoryURL.path })
        else { return nil }

        let project = Project(id: UUID(), name: name, path: directoryURL.path)
        projects.append(project)
        save()
        return project
    }

    @discardableResult
    func update(_ project: Project, name: String, directoryURL: URL) -> Project? {
        guard let index = projects.firstIndex(where: { $0.id == project.id }),
              let name = normalizedName(name),
              let directoryURL = canonicalDirectoryURL(for: directoryURL),
              !projects.contains(where: { $0.id != project.id && $0.path == directoryURL.path })
        else { return nil }

        let updated = Project(id: projects[index].id, name: name, path: directoryURL.path)
        projects[index] = updated
        save()
        return updated
    }

    func delete(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects.remove(at: index)
        save()
    }

    @discardableResult
    func moveProjects(fromOffsets sourceOffsets: IndexSet, toOffset destination: Int) -> Bool {
        guard !sourceOffsets.isEmpty,
              sourceOffsets.allSatisfy(projects.indices.contains),
              (0...projects.count).contains(destination)
        else { return false }

        let movingProjects = sourceOffsets.map { projects[$0] }
        var reorderedProjects = projects
        for index in sourceOffsets.reversed() {
            reorderedProjects.remove(at: index)
        }

        let insertionIndex = destination - sourceOffsets.filter { $0 < destination }.count
        reorderedProjects.insert(contentsOf: movingProjects, at: insertionIndex)
        guard reorderedProjects != projects else { return false }

        projects = reorderedProjects
        save()
        return true
    }

    func validatedDirectoryURL(for project: Project) -> URL? {
        guard let currentProject = projects.first(where: { $0.id == project.id }) else { return nil }
        return canonicalDirectoryURL(for: currentProject.directoryURL)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Project].self, from: data)
        else {
            projects = []
            return
        }

        projects = decoded.map(normalizedProject)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func normalizedName(_ name: String) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName.isEmpty ? nil : normalizedName
    }

    private func normalizedProject(_ project: Project) -> Project {
        let directoryURL = project.directoryURL.resolvingSymlinksInPath().standardizedFileURL
        return Project(
            id: project.id,
            name: project.name.trimmingCharacters(in: .whitespacesAndNewlines),
            path: directoryURL.path
        )
    }

    private func canonicalDirectoryURL(for directoryURL: URL) -> URL? {
        guard directoryURL.isFileURL else { return nil }

        let canonicalURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }

        return canonicalURL
    }
}
