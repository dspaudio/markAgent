import Foundation

struct GitChangedFile: Identifiable, Equatable {
    let rootURL: URL
    let relativePath: String
    let oldRelativePath: String?
    let status: String
    let diffSource: GitDiffSource

    var id: String { relativePath }
    var url: URL { rootURL.appendingPathComponent(relativePath) }
    var displayName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var parentPath: String { URL(fileURLWithPath: relativePath).deletingLastPathComponent().path }

    init(
        rootURL: URL,
        relativePath: String,
        oldRelativePath: String? = nil,
        status: String,
        diffSource: GitDiffSource = .workingTree
    ) {
        self.rootURL = rootURL
        self.relativePath = relativePath
        self.oldRelativePath = oldRelativePath
        self.status = status
        self.diffSource = diffSource
    }
}

struct GitFileDiff: Identifiable {
    let file: GitChangedFile
    let diffResult: DiffResult

    var id: String { file.id }
}

enum GitDiffSource: Equatable {
    case workingTree
    case commit(baseRevision: String, targetRevision: String)
}

struct GitCommitSummary: Equatable {
    let shortHash: String
    let subject: String

    var displayText: String {
        subject.isEmpty ? shortHash : "\(shortHash) \(subject)"
    }
}

@MainActor
@Observable
final class GitDiffState {
    private(set) var repositoryRoot: URL?
    private(set) var changedFiles: [GitChangedFile] = []
    private(set) var isShowingLastCommit = false
    private(set) var lastCommitSummary: GitCommitSummary?
    var selectedFile: GitChangedFile?
    var selectedDiffResult: DiffResult?
    private(set) var fileDiffs: [GitFileDiff] = []
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var isLoadingSelectedDiff = false
    private(set) var isLoadingDiffs = false
    var focusedFileID: String?
    private(set) var focusRequestID = 0
    private var refreshTask: Task<Void, Never>?
    private var selectTask: Task<Void, Never>?
    private var loadAllTask: Task<Void, Never>?
    private var refreshToken = 0
    private var selectToken = 0
    private var loadAllToken = 0

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
                        isShowingLastCommit: false,
                        lastCommitSummary: Optional<GitCommitSummary>.none,
                        errorMessage: Optional<String>.none
                    )
                }

                do {
                    let refreshResult = try Self.loadChangedFilesOrLastCommit(repositoryRoot: repositoryRoot)
                    return (
                        repositoryRoot: Optional(repositoryRoot),
                        changedFiles: refreshResult.files,
                        isShowingLastCommit: refreshResult.isShowingLastCommit,
                        lastCommitSummary: refreshResult.lastCommitSummary,
                        errorMessage: Optional<String>.none
                    )
                } catch {
                    return (
                        repositoryRoot: Optional(repositoryRoot),
                        changedFiles: [GitChangedFile](),
                        isShowingLastCommit: false,
                        lastCommitSummary: Optional<GitCommitSummary>.none,
                        errorMessage: Optional(error.localizedDescription)
                    )
                }
            }.value

            guard !Task.isCancelled, token == self.refreshToken else { return }
            self.repositoryRoot = result.repositoryRoot
            self.changedFiles = result.changedFiles
            self.isShowingLastCommit = result.isShowingLastCommit
            self.lastCommitSummary = result.lastCommitSummary
            self.errorMessage = result.errorMessage
            self.isRefreshing = false
            if result.repositoryRoot == nil {
                self.isShowingLastCommit = false
                self.lastCommitSummary = nil
                self.clearAllDiffs()
                self.clearSelection()
                return
            }

            if !self.fileDiffs.isEmpty || self.isLoadingDiffs {
                self.loadAllDiffs()
            }

            guard let selectedFile = self.selectedFile else { return }

            if let refreshedSelection = result.changedFiles.first(where: { $0.id == selectedFile.id }) {
                if refreshedSelection != selectedFile {
                    self.select(refreshedSelection)
                } else if self.selectedDiffResult == nil {
                    self.select(refreshedSelection)
                }
            } else {
                self.clearSelection()
            }
        }
    }

    func focus(_ file: GitChangedFile) {
        selectedFile = file
        focusedFileID = file.id
        focusRequestID += 1
        loadAllDiffs()
    }

    func loadAllDiffs() {
        loadAllToken += 1
        let token = loadAllToken
        let files = changedFiles
        loadAllTask?.cancel()

        guard repositoryRoot != nil else {
            clearAllDiffs()
            return
        }

        guard !files.isEmpty else {
            fileDiffs = []
            isLoadingDiffs = false
            return
        }

        isLoadingDiffs = true
        errorMessage = nil

        loadAllTask = Task { [files, token] in
            let diffs = await Task.detached(priority: .userInitiated) {
                files.map { file in
                    Self.loadFileDiff(file: file)
                }
            }.value

            guard !Task.isCancelled, token == self.loadAllToken else { return }
            self.fileDiffs = diffs
            self.isLoadingDiffs = false
            self.errorMessage = nil
        }
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
            let diffResult = await Task.detached(priority: .userInitiated) {
                let contents = Self.diffContents(for: file)
                return DiffEngine.compute(
                    old: contents.old,
                    new: contents.new,
                    emptyOldIsAllAdded: true
                )
            }.value
            guard !Task.isCancelled, token == self.selectToken, self.selectedFile?.id == file.id else { return }
            self.selectedFile = file
            self.selectedDiffResult = diffResult
            self.isLoadingSelectedDiff = false
            self.errorMessage = nil
        }
    }

    func clearSelection() {
        selectToken += 1
        selectTask?.cancel()
        selectedFile = nil
        selectedDiffResult = nil
        isLoadingSelectedDiff = false
    }

    private func clearAllDiffs() {
        loadAllToken += 1
        loadAllTask?.cancel()
        fileDiffs = []
        isLoadingDiffs = false
        focusedFileID = nil
        focusRequestID += 1
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

    private nonisolated static func loadChangedFilesOrLastCommit(repositoryRoot: URL) throws -> (
        files: [GitChangedFile],
        isShowingLastCommit: Bool,
        lastCommitSummary: GitCommitSummary?
    ) {
        let changedFiles = try loadChangedFiles(repositoryRoot: repositoryRoot)
        if !changedFiles.isEmpty {
            return (changedFiles, false, nil)
        }

        let lastCommitFiles = try loadLastCommitFiles(repositoryRoot: repositoryRoot)
        return (lastCommitFiles.files, !lastCommitFiles.files.isEmpty, lastCommitFiles.summary)
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

    private nonisolated static func loadLastCommitFiles(repositoryRoot: URL) throws -> (
        files: [GitChangedFile],
        summary: GitCommitSummary?
    ) {
        guard let summary = try loadLastCommitSummary(repositoryRoot: repositoryRoot) else {
            return ([], nil)
        }

        let output = try runGit(["diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "-M", "HEAD"], repositoryRoot: repositoryRoot)
        let files = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitChangedFile? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let rawStatus = parts.first, !rawStatus.isEmpty else { return nil }

                let relativePath: String
                let oldRelativePath: String?
                if rawStatus.hasPrefix("R"), parts.count >= 3 {
                    oldRelativePath = parts[1]
                    relativePath = parts[2]
                } else if parts.count >= 2 {
                    oldRelativePath = nil
                    relativePath = parts[1]
                } else {
                    return nil
                }

                return GitChangedFile(
                    rootURL: repositoryRoot,
                    relativePath: relativePath,
                    oldRelativePath: oldRelativePath,
                    status: rawStatus,
                    diffSource: .commit(baseRevision: "HEAD^", targetRevision: "HEAD")
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

        return (files, summary)
    }

    private nonisolated static func loadLastCommitSummary(repositoryRoot: URL) throws -> GitCommitSummary? {
        do {
            let output = try runGit(["log", "-1", "--format=%h%x00%s"], repositoryRoot: repositoryRoot)
            let parts = output.trimmingCharacters(in: .newlines).split(separator: Character("\u{0}"), maxSplits: 1, omittingEmptySubsequences: false)
            guard let shortHash = parts.first.map(String.init), !shortHash.isEmpty else { return nil }
            let subject = parts.count > 1 ? String(parts[1]) : ""
            return GitCommitSummary(shortHash: shortHash, subject: subject)
        } catch {
            return nil
        }
    }

    private nonisolated static func gitShow(_ revision: String, path: String, repositoryRoot: URL) throws -> String {
        try runGit(["show", "\(revision):\(path)"], repositoryRoot: repositoryRoot)
    }

    private nonisolated static func gitShowHead(file: GitChangedFile) throws -> String {
        do {
            return try gitShow("HEAD", path: file.relativePath, repositoryRoot: file.rootURL)
        } catch {
            return ""
        }
    }

    private nonisolated static func loadFileDiff(file: GitChangedFile) -> GitFileDiff {
        let contents = diffContents(for: file)
        let diffResult = DiffEngine.compute(
            old: contents.old,
            new: contents.new,
            emptyOldIsAllAdded: true
        )
        return GitFileDiff(file: file, diffResult: diffResult)
    }

    private nonisolated static func diffContents(for file: GitChangedFile) -> (old: String, new: String) {
        switch file.diffSource {
        case .workingTree:
            let oldContent = (try? gitShowHead(file: file)) ?? ""
            let newContent = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
            return (oldContent, newContent)
        case .commit(let baseRevision, let targetRevision):
            let oldPath = file.oldRelativePath ?? file.relativePath
            let oldContent = (try? gitShow(baseRevision, path: oldPath, repositoryRoot: file.rootURL)) ?? ""
            let newContent = (try? gitShow(targetRevision, path: file.relativePath, repositoryRoot: file.rootURL)) ?? ""
            return (oldContent, newContent)
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

        let outputData = PipeDataCollector()
        let errorData = PipeDataCollector()
        let readGroup = DispatchGroup()

        collectPipe(outputPipe, into: outputData, group: readGroup)
        collectPipe(errorPipe, into: errorData, group: readGroup)

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        process.waitUntilExit()
        readGroup.wait()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let output = String(data: outputData.snapshot(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData.snapshot(), encoding: .utf8) ?? ""
            throw GitDiffError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private nonisolated static func collectPipe(
        _ pipe: Pipe,
        into data: PipeDataCollector,
        group: DispatchGroup
    ) {
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                group.leave()
                return
            }

            data.append(chunk)
        }
    }
}

private final class PipeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return snapshot
    }
}

enum GitDiffError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? String(localized: "git 명령을 실행할 수 없습니다.") : message
        }
    }
}
