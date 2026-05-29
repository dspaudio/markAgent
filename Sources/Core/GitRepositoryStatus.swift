import Foundation

struct GitBranch: Identifiable, Equatable {
    enum Kind: Equatable {
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

struct GitRemoteBranchGroup: Identifiable, Equatable {
    let remoteName: String
    let branches: [GitBranch]

    var id: String { remoteName }
}

@MainActor
@Observable
final class GitRepositoryStatus {
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
    private var refreshToken = 0

    init(currentDirectory: URL) {
        self.currentDirectory = currentDirectory
    }

    var isInGitRepository: Bool {
        repositoryRoot != nil
    }

    func refresh(for directory: URL) {
        currentDirectory = directory
        refreshToken += 1
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
        guard let repositoryRoot else { return }
        isLoadingBranches = true
        checkoutErrorMessage = nil
        branchTask?.cancel()

        branchTask = Task { [repositoryRoot] in
            let result: Result<(local: [GitBranch], remoteGroups: [GitRemoteBranchGroup]), Error> = await Task.detached(priority: .utility) {
                Result {
                    try Self.loadBranches(repositoryRoot: repositoryRoot)
                }
            }.value

            guard !Task.isCancelled else { return }
            self.isLoadingBranches = false

            switch result {
            case .success(let branches):
                self.localBranches = branches.local
                self.remoteBranchGroups = branches.remoteGroups
            case .failure(let error):
                self.localBranches = []
                self.remoteBranchGroups = []
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
                return current
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

    private nonisolated static func runGitStrict(_ arguments: [String], repositoryRoot: URL) throws -> String {
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

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GitRepositoryStatusError.commandFailed(error.isEmpty ? output : error)
        }

        return output
    }
}

enum GitRepositoryStatusError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? String(localized: "git 명령을 실행할 수 없습니다.") : message
        }
    }
}
