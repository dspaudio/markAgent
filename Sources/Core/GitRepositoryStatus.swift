import Darwin
import Foundation

struct GitBranch: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case local
        case remote(String)
    }

    let kind: Kind
    let name: String

    var id: String {
        switch kind {
        case .local:
            return "local:\(name)"
        case .remote(let remote):
            return "remote:\(remote):\(name)"
        }
    }

    var displayName: String { name }

    var checkoutName: String {
        switch kind {
        case .local:
            return name
        case .remote(let remote):
            return "\(remote)/\(name)"
        }
    }
}

struct GitRemoteBranchGroup: Identifiable, Equatable, Sendable {
    let remoteName: String
    let branches: [GitBranch]

    var id: String { remoteName }
}

@MainActor
@Observable
final class GitRepositoryStatus {
    typealias BranchSnapshot = (
        branchName: String?,
        local: [GitBranch],
        remoteGroups: [GitRemoteBranchGroup]
    )
    typealias BranchSnapshotLoader = @Sendable (URL) throws -> BranchSnapshot
    typealias RemoteFetcher = @Sendable (URL, TimeInterval) throws -> Void

    private(set) var currentDirectory: URL
    private(set) var repositoryRoot: URL?
    private(set) var branchName: String?
    private(set) var localBranches: [GitBranch] = []
    private(set) var remoteBranchGroups: [GitRemoteBranchGroup] = []
    private(set) var isLoadingBranches = false
    private(set) var isInitializingRepository = false
    private(set) var isCheckingOut = false
    private(set) var checkoutTargetBranch: GitBranch?
    private(set) var checkoutErrorMessage: String?
    private var refreshTask: Task<Void, Never>?
    private var branchTask: Task<Void, Never>?
    private var checkoutTask: Task<Void, Never>?
    private var initTask: Task<Void, Never>?
    private var headWatcher: FileWatcher?
    private var watchedHeadURL: URL?
    private var refreshToken = 0
    private var branchGeneration = 0
    private var headWatcherToken = 0
    private let gitCommandTimeout: TimeInterval
    private let branchSnapshotLoader: BranchSnapshotLoader
    private let remoteFetcher: RemoteFetcher

    init(
        currentDirectory: URL,
        gitCommandTimeout: TimeInterval = 15,
        branchSnapshotLoader: @escaping BranchSnapshotLoader = GitRepositoryStatus.loadBranchSnapshot,
        remoteFetcher: @escaping RemoteFetcher = GitRepositoryStatus.fetchRemotes
    ) {
        self.currentDirectory = currentDirectory
        self.gitCommandTimeout = gitCommandTimeout
        self.branchSnapshotLoader = branchSnapshotLoader
        self.remoteFetcher = remoteFetcher
    }

    var isInGitRepository: Bool {
        repositoryRoot != nil
    }

    func refresh(for directory: URL) {
        currentDirectory = directory
        refreshToken += 1
        branchGeneration += 1
        branchTask?.cancel()
        branchTask = nil
        isLoadingBranches = false
        let token = refreshToken
        refreshTask?.cancel()

        refreshTask = Task { [directory, token] in
            let result = await Task.detached(priority: .utility) {
                let repositoryRoot = Self.findRepositoryRoot(from: directory)
                guard let repositoryRoot else {
                    return (repositoryRoot: Optional<URL>.none, branchName: Optional<String>.none)
                }

                return (
                    repositoryRoot: Optional(repositoryRoot),
                    branchName: Self.loadBranchName(repositoryRoot: repositoryRoot)
                )
            }.value

            guard !Task.isCancelled, token == self.refreshToken else { return }
            await self.updateHeadWatcher(repositoryRoot: result.repositoryRoot)
            guard !Task.isCancelled, token == self.refreshToken else { return }
            self.repositoryRoot = result.repositoryRoot
            self.branchName = result.branchName
            if result.repositoryRoot == nil {
                self.localBranches = []
                self.remoteBranchGroups = []
                self.checkoutErrorMessage = nil
            }
        }
    }

    func initializeRepository() {
        guard !isInGitRepository else { return }
        let directory = currentDirectory
        isInitializingRepository = true
        checkoutErrorMessage = nil
        initTask?.cancel()

        initTask = Task { [directory] in
            let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try Self.initializeRepository(at: directory)
                }
            }.value

            guard !Task.isCancelled else { return }
            self.isInitializingRepository = false

            switch result {
            case .success:
                self.refresh(for: directory)
            case .failure(let error):
                self.checkoutErrorMessage = error.localizedDescription
            }
        }
    }

    func loadBranches() {
        guard let repositoryRoot, !isLoadingBranches else { return }
        branchGeneration += 1
        let generation = branchGeneration
        let loader = branchSnapshotLoader
        isLoadingBranches = true
        checkoutErrorMessage = nil
        branchTask?.cancel()

        branchTask = Task { [repositoryRoot, generation, loader] in
            let operation = Task.detached(priority: .utility) {
                Result {
                    try loader(repositoryRoot)
                }
            }
            let result: Result<BranchSnapshot, Error> = await withTaskCancellationHandler {
                await operation.value
            } onCancel: {
                operation.cancel()
            }

            guard !Task.isCancelled,
                  generation == self.branchGeneration,
                  repositoryRoot == self.repositoryRoot else { return }
            self.isLoadingBranches = false
            self.branchTask = nil

            switch result {
            case .success(let branches):
                self.branchName = branches.branchName
                self.localBranches = branches.local
                self.remoteBranchGroups = branches.remoteGroups
            case .failure(let error):
                self.checkoutErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshBranchesFromRemotes() {
        guard let repositoryRoot, !isLoadingBranches, !isCheckingOut else { return }
        branchGeneration += 1
        let generation = branchGeneration
        let loader = branchSnapshotLoader
        let fetcher = remoteFetcher
        let timeout = gitCommandTimeout
        isLoadingBranches = true
        checkoutErrorMessage = nil

        branchTask = Task { [repositoryRoot, generation, loader, fetcher, timeout] in
            let operation = Task.detached(priority: .userInitiated) {
                Result {
                    try fetcher(repositoryRoot, timeout)
                    try Task.checkCancellation()
                    return try loader(repositoryRoot)
                }
            }
            let result: Result<BranchSnapshot, Error> = await withTaskCancellationHandler {
                await operation.value
            } onCancel: {
                operation.cancel()
            }

            guard !Task.isCancelled,
                  generation == self.branchGeneration,
                  repositoryRoot == self.repositoryRoot else { return }
            self.isLoadingBranches = false
            self.branchTask = nil

            switch result {
            case .success(let branches):
                self.branchName = branches.branchName
                self.localBranches = branches.local
                self.remoteBranchGroups = branches.remoteGroups
            case .failure(let error):
                self.checkoutErrorMessage = error.localizedDescription
            }
        }
    }

    func checkout(_ branch: GitBranch) {
        guard let repositoryRoot else {
            checkoutErrorMessage = String(localized: "Git 저장소가 아닙니다.")
            return
        }

        if branch.name == branchName {
            checkoutErrorMessage = String(format: String(localized: "이미 '%@' 브랜치에 있습니다."), branch.displayName)
            return
        }

        guard !isCheckingOut else {
            checkoutErrorMessage = String(localized: "다른 체크아웃 작업이 진행 중입니다.")
            return
        }

        isCheckingOut = true
        checkoutTargetBranch = branch
        checkoutErrorMessage = nil
        checkoutTask?.cancel()

        checkoutTask = Task { [repositoryRoot, branch] in
            let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try Self.checkout(branch, repositoryRoot: repositoryRoot)
                }
            }.value

            guard !Task.isCancelled else {
                self.isCheckingOut = false
                self.checkoutTargetBranch = nil
                return
            }

            self.isCheckingOut = false
            self.checkoutTargetBranch = nil

            switch result {
            case .success:
                self.refresh(for: self.currentDirectory)
                self.loadBranches()
            case .failure(let error):
                if let gitError = error as? GitRepositoryStatusError, case .commandFailed(let msg) = gitError {
                    self.checkoutErrorMessage = Self.parseCheckoutError(msg)
                } else {
                    self.checkoutErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private nonisolated static func findRepositoryRoot(from directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let gitURL = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitURL.path) {
                return URL(fileURLWithPath: current.path, isDirectory: false)
            }

            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return nil }
            current = parent
        }
    }

    private nonisolated static func loadBranchName(repositoryRoot: URL) -> String? {
        if let branch = try? runGit(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            repositoryRoot: repositoryRoot
        ), !branch.isEmpty {
            return branch
        }

        let shortHash = try? runGit(["rev-parse", "--short", "HEAD"], repositoryRoot: repositoryRoot)
        return shortHash.flatMap { $0.isEmpty ? nil : "HEAD@\($0)" }
    }

    private func updateHeadWatcher(repositoryRoot: URL?) async {
        let headURL = repositoryRoot.flatMap(Self.resolveHeadURL(repositoryRoot:))
        guard headURL != watchedHeadURL else { return }

        headWatcherToken += 1
        let token = headWatcherToken
        let previousWatcher = headWatcher
        watchedHeadURL = headURL
        let watcher = headURL.map { _ in
            FileWatcher { [weak self] in
                self?.refreshCurrentBranch()
            }
        }
        headWatcher = watcher

        await previousWatcher?.stopWatching()
        guard token == headWatcherToken, let watcher, let headURL else { return }
        await watcher.startWatching(url: headURL)
        if token != headWatcherToken {
            await watcher.stopWatching()
        }
    }

    private func refreshCurrentBranch() {
        guard let repositoryRoot else { return }
        let expectedRoot = repositoryRoot

        Task {
            let branchName = await Task.detached(priority: .utility) {
                Self.loadBranchName(repositoryRoot: expectedRoot)
            }.value
            guard self.repositoryRoot == expectedRoot else { return }
            self.branchName = branchName
        }
    }

    private nonisolated static func resolveHeadURL(repositoryRoot: URL) -> URL? {
        guard let gitDirectory = try? runGitStrict(
            ["rev-parse", "--absolute-git-dir"],
            repositoryRoot: repositoryRoot
        ), !gitDirectory.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: gitDirectory, isDirectory: true)
            .appendingPathComponent("HEAD", isDirectory: false)
            .standardizedFileURL
    }

    private nonisolated static func initializeRepository(at directory: URL) throws {
        _ = try runGitStrict(["init"], repositoryRoot: directory)
    }

    private nonisolated static func loadBranches(
        repositoryRoot: URL
    ) throws -> (local: [GitBranch], remoteGroups: [GitRemoteBranchGroup]) {
        let localOutput = try runGitStrict(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads"],
            repositoryRoot: repositoryRoot
        )
        let remoteOutput = try runGitStrict(
            ["for-each-ref", "--format=%(refname:short)", "refs/remotes"],
            repositoryRoot: repositoryRoot
        )

        let localBranches = localOutput
            .split(whereSeparator: \.isNewline)
            .map { GitBranch(kind: .local, name: String($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var remoteBranchesByName: [String: [GitBranch]] = [:]
        for line in remoteOutput.split(whereSeparator: \.isNewline) {
            let fullName = String(line)
            guard !fullName.hasSuffix("/HEAD") else { continue }
            let parts = fullName.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }

            let remote = String(parts[0])
            let branchName = String(parts[1])
            remoteBranchesByName[remote, default: []].append(GitBranch(kind: .remote(remote), name: branchName))
        }

        let remoteGroups = remoteBranchesByName
            .map { remoteName, branches in
                GitRemoteBranchGroup(
                    remoteName: remoteName,
                    branches: branches.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                )
            }
            .sorted { $0.remoteName.localizedStandardCompare($1.remoteName) == .orderedAscending }

        return (localBranches, remoteGroups)
    }

    private nonisolated static func loadBranchSnapshot(repositoryRoot: URL) throws -> BranchSnapshot {
        let branches = try loadBranches(repositoryRoot: repositoryRoot)
        return (
            branchName: loadBranchName(repositoryRoot: repositoryRoot),
            local: branches.local,
            remoteGroups: branches.remoteGroups
        )
    }

    private nonisolated static func fetchRemotes(repositoryRoot: URL, timeout: TimeInterval) throws {
        _ = try runGitStrict(
            ["fetch", "--all", "--prune"],
            repositoryRoot: repositoryRoot,
            timeout: timeout
        )
    }

    private nonisolated static func checkout(_ branch: GitBranch, repositoryRoot: URL) throws {
        switch branch.kind {
        case .local:
            _ = try runGitStrict(["checkout", branch.checkoutName], repositoryRoot: repositoryRoot)
        case .remote:
            if localBranchExists(named: branch.name, repositoryRoot: repositoryRoot) {
                _ = try runGitStrict(["checkout", branch.name], repositoryRoot: repositoryRoot)
            } else {
                _ = try runGitStrict(["checkout", "--track", branch.checkoutName], repositoryRoot: repositoryRoot)
            }
        }
    }

    private nonisolated static func parseCheckoutError(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("would be overwritten by checkout") {
            if lowercased.contains("untracked working tree files") {
                return String(localized: "추적되지 않는 파일이 덮어쓰여집니다. 먼저 파일을 커밋하거나 삭제해주세요.")
            } else {
                return String(localized: "커밋하지 않은 변경사항이 있습니다. 먼저 커밋하거나 스태시(stash)해주세요.")
            }
        } else if lowercased.contains("you need to resolve your current index first") || lowercased.contains("unmerged files") {
            return String(localized: "병합(merge) 충돌이 있습니다. 먼저 충돌을 해결해주세요.")
        }
        return message
    }

    private nonisolated static func localBranchExists(named branchName: String, repositoryRoot: URL) -> Bool {
        (try? runGitStrict(
            ["show-ref", "--verify", "--quiet", "refs/heads/\(branchName)"],
            repositoryRoot: repositoryRoot
        )) != nil
    }

    private nonisolated static func runGit(_ arguments: [String], repositoryRoot: URL) throws -> String {
        (try? runGitStrict(arguments, repositoryRoot: repositoryRoot)) ?? ""
    }

    private nonisolated static func runGitStrict(
        _ arguments: [String],
        repositoryRoot: URL,
        timeout: TimeInterval = 15
    ) throws -> String {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        return try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            currentDirectoryURL: repositoryRoot,
            environment: environment,
            timeout: timeout
        )
    }

    nonisolated static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval
    ) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment

        let captureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkAgent-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: captureDirectory) }

        let outputURL = captureDirectory.appendingPathComponent("stdout")
        let errorURL = captureDirectory.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let outputHandle = FileHandle(forWritingAtPath: outputURL.path),
              let errorHandle = FileHandle(forWritingAtPath: errorURL.path) else {
            throw GitRepositoryStatusError.commandFailed(String(localized: "git 명령을 실행할 수 없습니다."))
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while process.isRunning, !Task.isCancelled, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.2)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
        try outputHandle.close()
        try errorHandle.close()

        if Task.isCancelled {
            throw CancellationError()
        }
        if Date() >= deadline {
            throw GitRepositoryStatusError.commandTimedOut
        }

        let output = String(data: try Data(contentsOf: outputURL), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let error = String(data: try Data(contentsOf: errorURL), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GitRepositoryStatusError.commandFailed(error.isEmpty ? output : error)
        }

        return output
    }
}

enum GitRepositoryStatusError: LocalizedError {
    case commandFailed(String)
    case commandTimedOut

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? String(localized: "git 명령을 실행할 수 없습니다.") : message
        case .commandTimedOut:
            return String(localized: "git 명령이 시간 내에 완료되지 않았습니다.")
        }
    }
}
