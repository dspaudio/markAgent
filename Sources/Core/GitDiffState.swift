import Foundation

struct GitChangedFile: Identifiable, Equatable {
    let rootURL: URL
    let relativePath: String
    let status: String

    var id: String { relativePath }
    var url: URL { rootURL.appendingPathComponent(relativePath) }
    var displayName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var parentPath: String { URL(fileURLWithPath: relativePath).deletingLastPathComponent().path }
}

@MainActor
@Observable
final class GitDiffState {
    private(set) var repositoryRoot: URL?
    private(set) var changedFiles: [GitChangedFile] = []
    var selectedFile: GitChangedFile?
    var selectedDiffResult: DiffResult?
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var isLoadingSelectedDiff = false
    var isShowingSidebar = false
    private var refreshTask: Task<Void, Never>?
    private var selectTask: Task<Void, Never>?
    private var refreshToken = 0
    private var selectToken = 0

    var isInGitRepository: Bool { repositoryRoot != nil }

    func refresh(for directory: URL) {
        refreshToken += 1
        let token = refreshToken
        refreshTask?.cancel()
        errorMessage = nil
        isRefreshing = true

        refreshTask = Task { [directory, token] in
            let result = await Task.detached(priority: .utility) {
                let repositoryRoot = Self.findRepositoryRoot(from: directory)
                guard let repositoryRoot else {
                    return (
                        repositoryRoot: Optional<URL>.none,
                        changedFiles: [GitChangedFile](),
                        errorMessage: Optional<String>.none
                    )
                }

                do {
                    let changedFiles = try Self.loadChangedFiles(repositoryRoot: repositoryRoot)
                    return (
                        repositoryRoot: Optional(repositoryRoot),
                        changedFiles: changedFiles,
                        errorMessage: Optional<String>.none
                    )
                } catch {
                    return (
                        repositoryRoot: Optional(repositoryRoot),
                        changedFiles: [GitChangedFile](),
                        errorMessage: Optional(error.localizedDescription)
                    )
                }
            }.value

            guard !Task.isCancelled, token == self.refreshToken else { return }
            self.repositoryRoot = result.repositoryRoot
            self.changedFiles = result.changedFiles
            self.errorMessage = result.errorMessage
            self.isRefreshing = false
            if result.repositoryRoot == nil {
                self.isShowingSidebar = false
                self.clearSelection()
                return
            }

            guard let selectedFile = self.selectedFile else { return }

            if let refreshedSelection = result.changedFiles.first(where: { $0.id == selectedFile.id }) {
                if refreshedSelection != selectedFile {
                    self.selectedFile = refreshedSelection
                }
                if self.selectedDiffResult == nil {
                    self.select(refreshedSelection)
                }
            } else {
                self.clearSelection()
            }
        }
    }

    func toggleSidebar(for directory: URL) {
        guard isInGitRepository else { return }
        isShowingSidebar.toggle()
        refresh(for: directory)
    }

    func select(_ file: GitChangedFile) {
        selectToken += 1
        let token = selectToken
        selectedFile = file
        selectedDiffResult = nil
        isLoadingSelectedDiff = true
        errorMessage = nil
        selectTask?.cancel()

        selectTask = Task { [file, token] in
            do {
                let diffResult = try await Task.detached(priority: .userInitiated) {
                    let oldContent = try Self.gitShowHead(file: file)
                    let newContent = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
                    return DiffEngine.compute(
                        old: oldContent,
                        new: newContent,
                        emptyOldIsAllAdded: true
                    )
                }.value
                guard !Task.isCancelled, token == self.selectToken, self.selectedFile?.id == file.id else { return }
                self.selectedFile = file
                self.selectedDiffResult = diffResult
                self.isLoadingSelectedDiff = false
                self.errorMessage = nil
            } catch {
                guard !Task.isCancelled, token == self.selectToken, self.selectedFile?.id == file.id else { return }
                self.selectedDiffResult = nil
                self.isLoadingSelectedDiff = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func clearSelection() {
        selectToken += 1
        selectTask?.cancel()
        selectedFile = nil
        selectedDiffResult = nil
        isLoadingSelectedDiff = false
    }

    private nonisolated static func findRepositoryRoot(from directory: URL) -> URL? {
        var current = directory
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return nil }
            current = parent
        }
    }

    private nonisolated static func loadChangedFiles(repositoryRoot: URL) throws -> [GitChangedFile] {
        let output = try runGit(["status", "--porcelain=v1", "-uall"], repositoryRoot: repositoryRoot)
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitChangedFile? in
                guard line.count > 3 else { return nil }
                let status = String(line.prefix(2))
                var path = String(line.dropFirst(3))
                if let range = path.range(of: " -> ") {
                    path = String(path[range.upperBound...])
                }
                path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard !path.isEmpty else { return nil }
                return GitChangedFile(rootURL: repositoryRoot, relativePath: path, status: status)
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private nonisolated static func gitShowHead(file: GitChangedFile) throws -> String {
        do {
            return try runGit(["show", "HEAD:\(file.relativePath)"], repositoryRoot: file.rootURL)
        } catch {
            return ""
        }
    }

    private nonisolated static func runGit(_ arguments: [String], repositoryRoot: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitDiffError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

enum GitDiffError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "git 명령을 실행할 수 없습니다." : message
        }
    }
}
