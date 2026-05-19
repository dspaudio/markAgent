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
    var isShowingSidebar = false

    var isInGitRepository: Bool { repositoryRoot != nil }

    func refresh(for directory: URL) {
        repositoryRoot = Self.findRepositoryRoot(from: directory)
        selectedFile = nil
        selectedDiffResult = nil
        errorMessage = nil

        guard let repositoryRoot else {
            changedFiles = []
            isShowingSidebar = false
            return
        }

        do {
            changedFiles = try Self.loadChangedFiles(repositoryRoot: repositoryRoot)
        } catch {
            changedFiles = []
            errorMessage = error.localizedDescription
        }
    }

    func toggleSidebar(for directory: URL) {
        refresh(for: directory)
        guard isInGitRepository else { return }
        isShowingSidebar.toggle()
    }

    func select(_ file: GitChangedFile) {
        selectedFile = file
        do {
            let oldContent = try Self.gitShowHead(file: file)
            let newContent = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
            selectedDiffResult = DiffEngine.compute(
                old: oldContent,
                new: newContent,
                emptyOldIsAllAdded: true
            )
            errorMessage = nil
        } catch {
            selectedDiffResult = nil
            errorMessage = error.localizedDescription
        }
    }

    private static func findRepositoryRoot(from directory: URL) -> URL? {
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

    private static func loadChangedFiles(repositoryRoot: URL) throws -> [GitChangedFile] {
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

    private static func gitShowHead(file: GitChangedFile) throws -> String {
        do {
            return try runGit(["show", "HEAD:\(file.relativePath)"], repositoryRoot: file.rootURL)
        } catch {
            return ""
        }
    }

    private static func runGit(_ arguments: [String], repositoryRoot: URL) throws -> String {
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
