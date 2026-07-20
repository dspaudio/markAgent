import XCTest
@testable import ma

final class GitRepositoryStatusTests: XCTestCase {
    @MainActor
    func testCheckoutReportsWhenDirectoryIsNotGitRepository() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let status = GitRepositoryStatus(currentDirectory: directory)
        status.checkout(GitBranch(kind: .local, name: "main"))

        XCTAssertEqual(status.checkoutErrorMessage, "Git 저장소가 아닙니다.")
    }

    @MainActor
    func testCheckoutReportsWhenBranchIsAlreadyCurrent() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }

        let status = GitRepositoryStatus(currentDirectory: repository.root)
        status.refresh(for: repository.root)
        try await waitForGitStatusUpdate()

        status.checkout(GitBranch(kind: .local, name: repository.defaultBranch))

        XCTAssertEqual(status.checkoutErrorMessage, "이미 '\(repository.defaultBranch)' 브랜치에 있습니다.")
    }

    @MainActor
    func testCheckoutReportsFriendlyMessageForConflictingLocalChanges() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }

        let fileURL = repository.root.appendingPathComponent("notes.txt")

        _ = try runGit(["checkout", "-b", "feature"], in: repository.root)
        try "feature branch\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["commit", "-am", "feature update"], in: repository.root)

        _ = try runGit(["checkout", repository.defaultBranch], in: repository.root)
        try "local change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let status = GitRepositoryStatus(currentDirectory: repository.root)
        status.refresh(for: repository.root)
        try await waitForGitStatusUpdate()

        status.checkout(GitBranch(kind: .local, name: "feature"))
        try await waitForGitStatusUpdate()

        XCTAssertEqual(status.checkoutErrorMessage, "커밋하지 않은 변경사항이 있습니다. 먼저 커밋하거나 스태시(stash)해주세요.")
        XCTAssertFalse(status.isCheckingOut)
    }

    @MainActor
    func testExplicitRefreshUpdatesBranchAfterExternalCheckout() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }

        let status = GitRepositoryStatus(currentDirectory: repository.root)
        status.refresh(for: repository.root)
        let loadedInitialBranch = await waitUntil { status.branchName == repository.defaultBranch }
        XCTAssertTrue(loadedInitialBranch)

        _ = try runGit(["checkout", "-b", "external-feature"], in: repository.root)

        status.refresh(for: repository.root)

        let loadedExternalBranch = await waitUntil { status.branchName == "external-feature" }
        XCTAssertTrue(loadedExternalBranch)
    }

    @MainActor
    func testExternalCheckoutAutomaticallyRefreshesCurrentBranch() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }

        let status = GitRepositoryStatus(currentDirectory: repository.root)
        status.refresh(for: repository.root)
        let loadedInitialBranch = await waitUntil { status.branchName == repository.defaultBranch }
        XCTAssertTrue(loadedInitialBranch)

        _ = try runGit(["checkout", "-b", "externally-checked-out"], in: repository.root)

        let observedExternalCheckout = await waitUntil(timeout: .seconds(1)) {
            status.branchName == "externally-checked-out"
        }
        XCTAssertTrue(
            observedExternalCheckout,
            "외부 git checkout 후 refresh() 호출 없이 현재 브랜치가 갱신되어야 합니다. 실제 값: \(status.branchName ?? "nil")"
        )
    }

    @MainActor
    func testRefreshBranchesFromRemotesFetchesNewBranchAndPreservesBranchesOnFailure() async throws {
        let repository = try makeRepository()
        let remote = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString).git")
        let producer = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-Producer-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: repository.root)
            try? FileManager.default.removeItem(at: remote)
            try? FileManager.default.removeItem(at: producer)
        }

        _ = try runGit(["init", "--bare", remote.path], in: FileManager.default.temporaryDirectory)
        _ = try runGit(["remote", "add", "origin", remote.path], in: repository.root)
        _ = try runGit(["push", "-u", "origin", repository.defaultBranch], in: repository.root)

        let status = GitRepositoryStatus(currentDirectory: repository.root)
        status.refresh(for: repository.root)
        let foundRepository = await waitUntil { status.repositoryRoot == repository.root }
        XCTAssertTrue(foundRepository)

        status.loadBranches()
        let loadedInitialRemoteBranch = await waitUntil {
            self.hasRemoteBranch(repository.defaultBranch, remote: "origin", in: status.remoteBranchGroups)
        }
        XCTAssertTrue(loadedInitialRemoteBranch)

        _ = try runGit(["clone", remote.path, producer.path], in: FileManager.default.temporaryDirectory)
        _ = try runGit(
            ["checkout", "-b", "remote-feature", "origin/\(repository.defaultBranch)"],
            in: producer
        )
        let producerFile = producer.appendingPathComponent("remote-feature.txt")
        try "created after initial branch load\n".write(to: producerFile, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "remote-feature.txt"], in: producer)
        _ = try runGit(["commit", "-m", "add remote feature"], in: producer)
        _ = try runGit(["push", "-u", "origin", "remote-feature"], in: producer)

        status.refreshBranchesFromRemotes()
        let fetchedNewRemoteBranch = await waitUntil(timeout: .seconds(5)) {
            self.hasRemoteBranch("remote-feature", remote: "origin", in: status.remoteBranchGroups)
        }
        XCTAssertTrue(fetchedNewRemoteBranch, "최초 로드 이후 생성된 원격 브랜치를 fetch해야 합니다.")

        let branchesBeforeFailedFetch = status.remoteBranchGroups
        let unavailableRemote = remote.deletingLastPathComponent()
            .appendingPathComponent("missing-\(UUID().uuidString).git")
        _ = try runGit(["remote", "set-url", "origin", unavailableRemote.path], in: repository.root)

        status.refreshBranchesFromRemotes()
        XCTAssertTrue(status.isLoadingBranches)
        let failedFetchFinished = await waitUntil(timeout: .seconds(5)) { !status.isLoadingBranches }
        XCTAssertTrue(failedFetchFinished, "실패한 원격 fetch 작업이 bounded wait 안에 종료되어야 합니다.")
        XCTAssertEqual(
            status.remoteBranchGroups,
            branchesBeforeFailedFetch,
            "원격 fetch가 실패해도 마지막으로 성공한 브랜치 목록을 보존해야 합니다."
        )
    }

    private func makeRepository() throws -> (root: URL, defaultBranch: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fileURL = root.appendingPathComponent("notes.txt")
        _ = try runGit(["init"], in: root)
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "notes.txt"], in: root)
        _ = try runGit(["commit", "-m", "initial"], in: root)

        let branchName = try runGit(["symbolic-ref", "--short", "HEAD"], in: root)
        return (root, branchName)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "LANG": "C",
            "GIT_AUTHOR_NAME": "MarkAgent",
            "GIT_AUTHOR_EMAIL": "markagent@example.com",
            "GIT_COMMITTER_NAME": "MarkAgent",
            "GIT_COMMITTER_EMAIL": "markagent@example.com",
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(domain: "GitRepositoryStatusTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: error.isEmpty ? output : error,
            ])
        }

        return output
    }

    private func hasRemoteBranch(
        _ branchName: String,
        remote remoteName: String,
        in groups: [GitRemoteBranchGroup]
    ) -> Bool {
        groups.first(where: { $0.remoteName == remoteName })?
            .branches
            .contains(where: { $0.name == branchName }) == true
    }

    @MainActor
    private func waitForGitStatusUpdate() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        return condition()
    }
}
