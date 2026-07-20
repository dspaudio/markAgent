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
    typealias BranchNameLoader = @Sendable (URL) -> String?
    typealias RepositoryInitializer = @Sendable (URL) throws -> Void
    typealias BranchCheckout = @Sendable (GitBranch, URL) throws -> Void

    private(set) var currentDirectory: URL
    private(set) var repositoryRoot: URL?
    private(set) var branchName: String?
    private(set) var localBranches: [GitBranch] = []
    private(set) var remoteBranchGroups: [GitRemoteBranchGroup] = []
    private(set) var isLoadingBranches = false
    private(set) var isRefreshingRemotes = false
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
    private var branchNameGeneration = 0
    private var checkoutGeneration = 0
    private var initGeneration = 0
    private var headWatcherToken = 0
    private let gitCommandTimeout: TimeInterval
    private let branchSnapshotLoader: BranchSnapshotLoader
    private let remoteFetcher: RemoteFetcher
    private let branchNameLoader: BranchNameLoader
    private let repositoryInitializer: RepositoryInitializer
    private let branchCheckout: BranchCheckout

    init(
        currentDirectory: URL,
        gitCommandTimeout: TimeInterval = 15,
        branchSnapshotLoader: @escaping BranchSnapshotLoader = GitRepositoryStatus.loadBranchSnapshot,
        remoteFetcher: @escaping RemoteFetcher = GitRepositoryStatus.fetchRemotes,
        branchNameLoader: @escaping BranchNameLoader = GitRepositoryStatus.loadBranchName,
        repositoryInitializer: @escaping RepositoryInitializer = GitRepositoryStatus.initializeRepository,
        branchCheckout: @escaping BranchCheckout = GitRepositoryStatus.checkout
    ) {
        self.currentDirectory = currentDirectory
        self.gitCommandTimeout = gitCommandTimeout
        self.branchSnapshotLoader = branchSnapshotLoader
        self.remoteFetcher = remoteFetcher
        self.branchNameLoader = branchNameLoader
        self.repositoryInitializer = repositoryInitializer
        self.branchCheckout = branchCheckout
    }

    var isInGitRepository: Bool {
        repositoryRoot != nil
    }

    func refresh(for directory: URL) {
        let standardizedDirectory = directory.standardizedFileURL
        let directoryChanged = standardizedDirectory != currentDirectory.standardizedFileURL
        currentDirectory = standardizedDirectory
        refreshToken += 1
        branchGeneration += 1
        branchNameGeneration += 1
        let nameGeneration = branchNameGeneration
        branchTask?.cancel()
        branchTask = nil
        isLoadingBranches = false
        isRefreshingRemotes = false
        let token = refreshToken
        refreshTask?.cancel()

        if directoryChanged {
            checkoutGeneration += 1
            checkoutTask?.cancel()
            checkoutTask = nil
            isCheckingOut = false
            checkoutTargetBranch = nil
            initGeneration += 1
            initTask?.cancel()
            initTask = nil
            isInitializingRepository = false
            repositoryRoot = nil
            branchName = nil
            localBranches = []
            remoteBranchGroups = []
            checkoutErrorMessage = nil
        }

        let branchNameLoader = branchNameLoader
        refreshTask = Task { [directory = standardizedDirectory, token, nameGeneration, branchNameLoader] in
            let result = await Task.detached(priority: .utility) {
                let repositoryRoot = Self.findRepositoryRoot(from: directory)
                guard let repositoryRoot else {
                    return (repositoryRoot: Optional<URL>.none, branchName: Optional<String>.none)
                }

                return (
                    repositoryRoot: Optional(repositoryRoot),
                    branchName: branchNameLoader(repositoryRoot)
                )
            }.value

            guard !Task.isCancelled, token == self.refreshToken else { return }
            await self.updateHeadWatcher(repositoryRoot: result.repositoryRoot)
            guard !Task.isCancelled, token == self.refreshToken else { return }
            self.repositoryRoot = result.repositoryRoot
            if nameGeneration == self.branchNameGeneration {
                self.branchName = result.branchName
            }
            if result.repositoryRoot == nil {
                self.localBranches = []
                self.remoteBranchGroups = []
                self.checkoutErrorMessage = nil
            } else {
                self.loadBranches()
            }
        }
    }

    func initializeRepository() {
        guard !isInGitRepository else { return }
        let directory = currentDirectory
        initGeneration += 1
        let generation = initGeneration
        let initializer = repositoryInitializer
        isInitializingRepository = true
        checkoutErrorMessage = nil
        initTask?.cancel()

        initTask = Task { [directory, generation, initializer] in
            let operation = Task.detached(priority: .userInitiated) {
                Result {
                    try initializer(directory)
                }
            }
            let result: Result<Void, Error> = await withTaskCancellationHandler {
                await operation.value
            } onCancel: {
                operation.cancel()
            }

            guard !Task.isCancelled,
                  generation == self.initGeneration,
                  directory.standardizedFileURL == self.currentDirectory.standardizedFileURL else { return }
            self.isInitializingRepository = false
            self.initTask = nil

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
        branchNameGeneration += 1
        let nameGeneration = branchNameGeneration
        let loader = branchSnapshotLoader
        isLoadingBranches = true
        isRefreshingRemotes = false
        checkoutErrorMessage = nil
        branchTask?.cancel()

        branchTask = Task { [repositoryRoot, generation, nameGeneration, loader] in
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
            self.isRefreshingRemotes = false
            self.branchTask = nil

            switch result {
            case .success(let branches):
                if nameGeneration == self.branchNameGeneration {
                    self.branchName = branches.branchName
                }
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
        branchNameGeneration += 1
        let nameGeneration = branchNameGeneration
        let loader = branchSnapshotLoader
        let fetcher = remoteFetcher
        let timeout = gitCommandTimeout
        isLoadingBranches = true
        isRefreshingRemotes = true
        checkoutErrorMessage = nil

        branchTask = Task { [repositoryRoot, generation, nameGeneration, loader, fetcher, timeout] in
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
            self.isRefreshingRemotes = false
            self.branchTask = nil

            switch result {
            case .success(let branches):
                if nameGeneration == self.branchNameGeneration {
                    self.branchName = branches.branchName
                }
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

        guard !isCheckingOut, !isLoadingBranches else {
            checkoutErrorMessage = String(localized: "다른 체크아웃 작업이 진행 중입니다.")
            return
        }

        checkoutGeneration += 1
        let generation = checkoutGeneration
        let directory = currentDirectory
        let checkout = branchCheckout
        isCheckingOut = true
        checkoutTargetBranch = branch
        checkoutErrorMessage = nil
        checkoutTask?.cancel()

        checkoutTask = Task { [repositoryRoot, directory, branch, generation, checkout] in
            let operation = Task.detached(priority: .userInitiated) {
                Result {
                    try checkout(branch, repositoryRoot)
                }
            }
            let result: Result<Void, Error> = await withTaskCancellationHandler {
                await operation.value
            } onCancel: {
                operation.cancel()
            }

            guard !Task.isCancelled,
                  generation == self.checkoutGeneration,
                  repositoryRoot == self.repositoryRoot,
                  directory.standardizedFileURL == self.currentDirectory.standardizedFileURL else { return }

            self.isCheckingOut = false
            self.checkoutTargetBranch = nil
            self.checkoutTask = nil

            switch result {
            case .success:
                self.refresh(for: directory)
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

    func refreshCurrentBranch() {
        guard let repositoryRoot else { return }
        let expectedRoot = repositoryRoot
        branchNameGeneration += 1
        let generation = branchNameGeneration
        let loader = branchNameLoader

        Task {
            let branchName = await Task.detached(priority: .utility) {
                loader(expectedRoot)
            }.value
            guard generation == self.branchNameGeneration,
                  self.repositoryRoot == expectedRoot else { return }
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
        var outputDescriptors = [Int32](repeating: -1, count: 2)
        var errorDescriptors = [Int32](repeating: -1, count: 2)
        guard outputDescriptors.withUnsafeMutableBufferPointer({ Darwin.pipe($0.baseAddress!) }) == 0,
              errorDescriptors.withUnsafeMutableBufferPointer({ Darwin.pipe($0.baseAddress!) }) == 0 else {
            outputDescriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
            throw GitRepositoryStatusError.commandFailed(String(localized: "git 명령을 실행할 수 없습니다."))
        }
        defer {
            Darwin.close(outputDescriptors[0])
            Darwin.close(errorDescriptors[0])
        }

        for descriptor in [outputDescriptors[0], errorDescriptors[0]] {
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 {
                _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
            }
        }

        let processIdentifier: pid_t
        do {
            processIdentifier = try spawnProcess(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                environment: environment,
                standardOutput: outputDescriptors,
                standardError: errorDescriptors
            )
        } catch {
            Darwin.close(outputDescriptors[1])
            Darwin.close(errorDescriptors[1])
            throw error
        }
        Darwin.close(outputDescriptors[1])
        Darwin.close(errorDescriptors[1])

        var outputCapture = BoundedOutputCapture(limit: 256 * 1024)
        var errorCapture = BoundedOutputCapture(limit: 256 * 1024)
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        var waitStatus: Int32 = 0
        var hasExited = false
        var wasCancelled = false
        var didTimeOut = false

        while !hasExited {
            outputCapture.drain(descriptor: outputDescriptors[0])
            errorCapture.drain(descriptor: errorDescriptors[0])
            let waitResult = waitpid(processIdentifier, &waitStatus, WNOHANG)
            if waitResult == processIdentifier {
                hasExited = true
                break
            }
            if waitResult == -1, errno != EINTR {
                throw GitRepositoryStatusError.commandFailed(String(localized: "git 명령을 실행할 수 없습니다."))
            }
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            if Date() >= deadline {
                didTimeOut = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        if wasCancelled || didTimeOut {
            terminateProcessGroup(
                processIdentifier,
                waitStatus: &waitStatus,
                hasExited: &hasExited,
                outputDescriptor: outputDescriptors[0],
                errorDescriptor: errorDescriptors[0],
                outputCapture: &outputCapture,
                errorCapture: &errorCapture
            )
        }
        outputCapture.drain(descriptor: outputDescriptors[0])
        errorCapture.drain(descriptor: errorDescriptors[0])

        if wasCancelled {
            throw CancellationError()
        }
        if didTimeOut {
            throw GitRepositoryStatusError.commandTimedOut
        }

        let output = outputCapture.string
        guard waitStatus == 0 else {
            let error = errorCapture.string
            throw GitRepositoryStatusError.commandFailed(
                redactSensitiveURLParts(in: error.isEmpty ? output : error)
            )
        }

        return output
    }

    private nonisolated static func spawnProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String],
        standardOutput: [Int32],
        standardError: [Int32]
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw GitRepositoryStatusError.commandFailed(String(localized: "git 명령을 실행할 수 없습니다."))
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw GitRepositoryStatusError.commandFailed(String(localized: "git 명령을 실행할 수 없습니다."))
        }
        defer { posix_spawnattr_destroy(&attributes) }

        guard posix_spawn_file_actions_addchdir_np(&fileActions, currentDirectoryURL.path) == 0,
              posix_spawn_file_actions_adddup2(&fileActions, standardOutput[1], STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&fileActions, standardError[1], STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&fileActions, standardOutput[0]) == 0,
              posix_spawn_file_actions_addclose(&fileActions, standardError[0]) == 0,
              posix_spawn_file_actions_addclose(&fileActions, standardOutput[1]) == 0,
              posix_spawn_file_actions_addclose(&fileActions, standardError[1]) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            throw GitRepositoryStatusError.commandFailed(String(localized: "git 명령을 실행할 수 없습니다."))
        }

        let argumentPointers = ([executableURL.path] + arguments).map { strdup($0) } + [nil]
        let environmentPointers = environment
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argumentPointers.compactMap { $0 }.forEach { free($0) }
            environmentPointers.compactMap { $0 }.forEach { free($0) }
        }

        var processIdentifier: pid_t = 0
        let result = argumentPointers.withUnsafeBufferPointer { argumentsBuffer in
            environmentPointers.withUnsafeBufferPointer { environmentBuffer in
                posix_spawn(
                    &processIdentifier,
                    executableURL.path,
                    &fileActions,
                    &attributes,
                    UnsafeMutablePointer(mutating: argumentsBuffer.baseAddress!),
                    UnsafeMutablePointer(mutating: environmentBuffer.baseAddress!)
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
        }
        return processIdentifier
    }

    private nonisolated static func terminateProcessGroup(
        _ processIdentifier: pid_t,
        waitStatus: inout Int32,
        hasExited: inout Bool,
        outputDescriptor: Int32,
        errorDescriptor: Int32,
        outputCapture: inout BoundedOutputCapture,
        errorCapture: inout BoundedOutputCapture
    ) {
        _ = kill(-processIdentifier, SIGTERM)
        let terminationDeadline = Date().addingTimeInterval(0.2)
        while Date() < terminationDeadline {
            outputCapture.drain(descriptor: outputDescriptor)
            errorCapture.drain(descriptor: errorDescriptor)
            Thread.sleep(forTimeInterval: 0.01)
        }

        _ = kill(-processIdentifier, SIGKILL)
        while waitpid(processIdentifier, &waitStatus, 0) == -1, errno == EINTR {}
        hasExited = true
    }

    private nonisolated static func redactSensitiveURLParts(in message: String) -> String {
        guard let detector = try? NSRegularExpression(pattern: #"https?://[^\s<>\"']+"#) else {
            return message
        }
        let range = NSRange(message.startIndex..., in: message)
        return detector.matches(in: message, range: range).reversed().reduce(into: message) { result, match in
            guard let matchRange = Range(match.range, in: result),
                  var components = URLComponents(string: String(result[matchRange])) else { return }
            if components.user != nil { components.user = "REDACTED" }
            if components.password != nil { components.password = "REDACTED" }
            components.queryItems = components.queryItems?.map { item in
                URLQueryItem(name: item.name, value: item.value == nil ? nil : "REDACTED")
            }
            if let redacted = components.string {
                result.replaceSubrange(matchRange, with: redacted)
            }
        }
    }
}

private struct BoundedOutputCapture {
    private let limit: Int
    private var data = Data()
    private var discardedBytes = 0

    init(limit: Int) {
        self.limit = limit
    }

    mutating func drain(descriptor: Int32) {
        var bytes = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            guard count > 0 else {
                if count == -1, errno == EINTR { continue }
                return
            }
            data.append(contentsOf: bytes.prefix(Int(count)))
            if data.count > limit {
                let overflow = data.count - limit
                data.removeFirst(overflow)
                discardedBytes += overflow
            }
        }
    }

    var string: String {
        let content = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard discardedBytes > 0 else { return content }
        return "[\(discardedBytes) bytes truncated]\n\(content)"
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
