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
    func testLateBranchSnapshotDoesNotOverwriteNewerHeadRefresh() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let snapshotLoader = BlockingBranchSnapshotLoader(branchName: "stale-branch")
        let branchNameLoader = SequencedBranchNameLoader(values: ["initial-branch", "newest-branch"])
        let status = GitRepositoryStatus(
            currentDirectory: repository.root,
            branchSnapshotLoader: { _ in try snapshotLoader.load() },
            branchNameLoader: { _ in branchNameLoader.load() }
        )

        status.refresh(for: repository.root)
        let initialLoadFinished = await waitUntil {
            snapshotLoader.callCount == 1 && !status.isLoadingBranches
        }
        XCTAssertTrue(initialLoadFinished)

        status.loadBranches()
        let staleLoadStarted = await waitUntil { snapshotLoader.callCount == 2 }
        XCTAssertTrue(staleLoadStarted)

        status.refreshCurrentBranch()
        let newestHeadLoaded = await waitUntil { status.branchName == "newest-branch" }
        XCTAssertTrue(newestHeadLoaded)

        snapshotLoader.finishBlockedLoad()
        let staleLoadFinished = await waitUntil { !status.isLoadingBranches }
        XCTAssertTrue(staleLoadFinished)
        XCTAssertEqual(status.branchName, "newest-branch")
    }

    @MainActor
    func testOutOfOrderHeadRefreshKeepsNewestBranchName() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let branchNameLoader = BlockingBranchNameLoader()
        let status = GitRepositoryStatus(
            currentDirectory: repository.root,
            branchNameLoader: { _ in branchNameLoader.load() }
        )

        status.refresh(for: repository.root)
        let repositoryLoaded = await waitUntil { status.repositoryRoot == repository.root }
        XCTAssertTrue(repositoryLoaded)

        status.refreshCurrentBranch()
        let staleRefreshStarted = await waitUntil { branchNameLoader.callCount == 2 }
        XCTAssertTrue(staleRefreshStarted)
        status.refreshCurrentBranch()
        let newestRefreshFinished = await waitUntil { status.branchName == "newest-branch" }
        XCTAssertTrue(newestRefreshFinished)

        branchNameLoader.finishStaleLoad()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(status.branchName, "newest-branch")
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
        let foundRepository = await waitUntil {
            status.repositoryRoot == repository.root && !status.isLoadingBranches
        }
        XCTAssertTrue(foundRepository)

        let loadedInitialRemoteBranch = await waitUntil {
            !status.isLoadingBranches
                && self.hasRemoteBranch(repository.defaultBranch, remote: "origin", in: status.remoteBranchGroups)
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

    @MainActor
    func testRemoteRefreshRejectsDuplicateRequestWhileLoading() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let fetcher = BlockingRemoteFetcher()
        let status = GitRepositoryStatus(
            currentDirectory: repository.root,
            remoteFetcher: { _, _ in try fetcher.fetch() }
        )

        status.refresh(for: repository.root)
        let foundRepository = await waitUntil {
            status.repositoryRoot == repository.root && !status.isLoadingBranches
        }
        XCTAssertTrue(foundRepository)

        status.refreshBranchesFromRemotes()
        let startedRefresh = await waitUntil { fetcher.callCount == 1 }
        XCTAssertTrue(startedRefresh)
        XCTAssertTrue(status.isLoadingBranches)
        XCTAssertTrue(status.isRefreshingRemotes)

        status.refreshBranchesFromRemotes()
        XCTAssertEqual(fetcher.callCount, 1, "로딩 중에는 중복 Remote refresh를 시작하지 않아야 합니다.")

        fetcher.finish()
        let finishedRefresh = await waitUntil { !status.isLoadingBranches }
        XCTAssertTrue(finishedRefresh)
        XCTAssertFalse(status.isRefreshingRemotes)
        XCTAssertEqual(fetcher.callCount, 1)
    }

    @MainActor
    func testRepositoryChangeIgnoresInFlightRemoteRefreshResult() async throws {
        let repositoryA = try makeRepository()
        let repositoryB = try makeRepository()
        defer {
            try? FileManager.default.removeItem(at: repositoryA.root)
            try? FileManager.default.removeItem(at: repositoryB.root)
        }
        _ = try runGit(["branch", "repo-b-only"], in: repositoryB.root)

        let fetcher = BlockingRemoteFetcher()
        let status = GitRepositoryStatus(
            currentDirectory: repositoryA.root,
            remoteFetcher: { _, _ in try fetcher.fetch() }
        )
        status.refresh(for: repositoryA.root)
        let foundRepositoryA = await waitUntil {
            status.repositoryRoot == repositoryA.root && !status.isLoadingBranches
        }
        XCTAssertTrue(foundRepositoryA)

        status.refreshBranchesFromRemotes()
        let startedRefresh = await waitUntil { fetcher.callCount == 1 }
        XCTAssertTrue(startedRefresh)
        XCTAssertTrue(status.isLoadingBranches)
        XCTAssertTrue(status.isRefreshingRemotes)

        status.refresh(for: repositoryB.root)
        let foundRepositoryB = await waitUntil {
            status.repositoryRoot == repositoryB.root
                && !status.isLoadingBranches
                && status.localBranches.contains(where: { $0.name == "repo-b-only" })
        }
        XCTAssertTrue(foundRepositoryB)
        XCTAssertFalse(status.isRefreshingRemotes)

        fetcher.finish()
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(status.repositoryRoot, repositoryB.root)
        XCTAssertTrue(status.localBranches.contains(where: { $0.name == "repo-b-only" }))
        XCTAssertFalse(status.isLoadingBranches)
        XCTAssertFalse(status.isRefreshingRemotes)
    }

    @MainActor
    func testRepositoryChangeImmediatelyClearsOldBranchesAndLoadsNewRepository() async throws {
        let repositoryA = try makeRepository()
        let repositoryB = try makeRepository()
        defer {
            try? FileManager.default.removeItem(at: repositoryA.root)
            try? FileManager.default.removeItem(at: repositoryB.root)
        }
        _ = try runGit(["branch", "repo-a-only"], in: repositoryA.root)
        _ = try runGit(["branch", "repo-b-only"], in: repositoryB.root)
        let status = GitRepositoryStatus(currentDirectory: repositoryA.root)

        status.refresh(for: repositoryA.root)
        let loadedRepositoryA = await waitUntil {
            status.repositoryRoot == repositoryA.root
                && status.localBranches.contains(where: { $0.name == "repo-a-only" })
        }
        XCTAssertTrue(loadedRepositoryA)

        status.refresh(for: repositoryB.root)

        XCTAssertNil(status.repositoryRoot)
        XCTAssertNil(status.branchName)
        XCTAssertTrue(status.localBranches.isEmpty)
        XCTAssertTrue(status.remoteBranchGroups.isEmpty)

        let loadedRepositoryB = await waitUntil {
            status.repositoryRoot == repositoryB.root
                && status.localBranches.contains(where: { $0.name == "repo-b-only" })
                && !status.localBranches.contains(where: { $0.name == "repo-a-only" })
        }
        XCTAssertTrue(loadedRepositoryB)
    }

    @MainActor
    func testLateCheckoutCompletionDoesNotClearNewRepositoryCheckoutState() async throws {
        let repositoryA = try makeRepository()
        let repositoryB = try makeRepository()
        defer {
            try? FileManager.default.removeItem(at: repositoryA.root)
            try? FileManager.default.removeItem(at: repositoryB.root)
        }
        let checkout = BlockingCheckoutOperation(firstRoot: repositoryA.root, secondRoot: repositoryB.root)
        let status = GitRepositoryStatus(
            currentDirectory: repositoryA.root,
            branchCheckout: { branch, root in try checkout.run(branch: branch, root: root) }
        )

        status.refresh(for: repositoryA.root)
        let repositoryALoaded = await waitUntil {
            status.repositoryRoot == repositoryA.root && !status.isLoadingBranches
        }
        XCTAssertTrue(repositoryALoaded)
        let branchA = GitBranch(kind: .local, name: "repo-a-target")
        status.checkout(branchA)
        let firstCheckoutStarted = await waitUntil { checkout.firstCallStarted }
        XCTAssertTrue(firstCheckoutStarted)

        status.refresh(for: repositoryB.root)
        let repositoryBLoaded = await waitUntil {
            status.repositoryRoot == repositoryB.root && !status.isLoadingBranches
        }
        XCTAssertTrue(repositoryBLoaded)
        let branchB = GitBranch(kind: .local, name: "repo-b-target")
        status.checkout(branchB)
        let secondCheckoutStarted = await waitUntil { checkout.secondCallStarted }
        XCTAssertTrue(secondCheckoutStarted)

        checkout.finishFirst()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(status.isCheckingOut)
        XCTAssertEqual(status.checkoutTargetBranch, branchB)
        XCTAssertEqual(status.currentDirectory.path, repositoryB.root.path)

        checkout.finishSecond()
        let secondCheckoutFinished = await waitUntil { !status.isCheckingOut }
        XCTAssertTrue(secondCheckoutFinished)
    }

    @MainActor
    func testLateRepositoryInitCompletionDoesNotReactivateOldDirectory() async throws {
        let directoryA = try makeTemporaryDirectory()
        let directoryB = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }
        let initializer = BlockingRepositoryInitializer(firstDirectory: directoryA, secondDirectory: directoryB)
        let status = GitRepositoryStatus(
            currentDirectory: directoryA,
            repositoryInitializer: { directory in try initializer.run(directory: directory) }
        )

        status.initializeRepository()
        let firstInitStarted = await waitUntil { initializer.firstCallStarted }
        XCTAssertTrue(firstInitStarted)

        status.refresh(for: directoryB)
        XCTAssertFalse(status.isInitializingRepository)
        status.initializeRepository()
        let secondInitStarted = await waitUntil { initializer.secondCallStarted }
        XCTAssertTrue(secondInitStarted)

        initializer.finishFirst()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(status.currentDirectory.path, directoryB.path)
        XCTAssertTrue(status.isInitializingRepository)

        initializer.finishSecond()
        let secondInitFinished = await waitUntil { !status.isInitializingRepository }
        XCTAssertTrue(secondInitFinished)
        XCTAssertEqual(status.currentDirectory.path, directoryB.path)
    }

    @MainActor
    func testCheckoutIsRejectedWhileBranchesAreLoading() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let fetcher = BlockingRemoteFetcher()
        let checkout = CheckoutCallRecorder()
        let status = GitRepositoryStatus(
            currentDirectory: repository.root,
            remoteFetcher: { _, _ in try fetcher.fetch() },
            branchCheckout: { branch, root in checkout.record(branch: branch, root: root) }
        )

        status.refresh(for: repository.root)
        let repositoryLoaded = await waitUntil {
            status.repositoryRoot == repository.root && !status.isLoadingBranches
        }
        XCTAssertTrue(repositoryLoaded)
        status.refreshBranchesFromRemotes()
        let refreshStarted = await waitUntil { status.isLoadingBranches && fetcher.callCount == 1 }
        XCTAssertTrue(refreshStarted)

        status.checkout(GitBranch(kind: .local, name: "loading-target"))
        XCTAssertEqual(checkout.callCount, 0)
        XCTAssertFalse(status.isCheckingOut)

        fetcher.finish()
        let refreshFinished = await waitUntil { !status.isLoadingBranches }
        XCTAssertTrue(refreshFinished)
    }

    @MainActor
    func testRepositoryRefreshCancelsRemoteRefreshAndClearsDedicatedState() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let fetcher = BlockingRemoteFetcher()
        let status = GitRepositoryStatus(
            currentDirectory: repository.root,
            remoteFetcher: { _, _ in try fetcher.fetch() }
        )

        status.refresh(for: repository.root)
        let foundRepository = await waitUntil {
            status.repositoryRoot == repository.root && !status.isLoadingBranches
        }
        XCTAssertTrue(foundRepository)

        status.refreshBranchesFromRemotes()
        let startedRefresh = await waitUntil { fetcher.callCount == 1 }
        XCTAssertTrue(startedRefresh)
        XCTAssertTrue(status.isLoadingBranches)
        XCTAssertTrue(status.isRefreshingRemotes)

        status.refresh(for: repository.root)

        XCTAssertFalse(status.isRefreshingRemotes)
        let reloadedBranches = await waitUntil { !status.isLoadingBranches }
        XCTAssertTrue(reloadedBranches)
        fetcher.finish()
    }

    func testRunProcessTimesOutAndTerminatesHungCommand() throws {
        let start = ContinuousClock.now

        XCTAssertThrowsError(
            try GitRepositoryStatus.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                currentDirectoryURL: FileManager.default.temporaryDirectory,
                timeout: 0.1
            )
        ) { error in
            guard case GitRepositoryStatusError.commandTimedOut = error else {
                return XCTFail("예상하지 못한 오류: \(error)")
            }
        }

        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }

    func testRunProcessCancellationTerminatesHungCommand() async {
        let task = Task.detached {
            try GitRepositoryStatus.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                currentDirectoryURL: FileManager.default.temporaryDirectory,
                timeout: 5
            )
        }
        try? await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소된 프로세스가 성공하면 안 됩니다.")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }

    func testRunProcessTimeoutTerminatesSignalIgnoringDescendant() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descendantPIDURL = fixture.appendingPathComponent("descendant.pid")

        XCTAssertThrowsError(
            try GitRepositoryStatus.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", signalIgnoringProcessTreeScript(pidFile: descendantPIDURL.path)],
                currentDirectoryURL: fixture,
                timeout: 0.3
            )
        ) { error in
            guard case GitRepositoryStatusError.commandTimedOut = error else {
                return XCTFail("예상하지 못한 오류: \(error)")
            }
        }

        let descendantPID = try readPID(from: descendantPIDURL)
        XCTAssertTrue(
            waitForProcessToExit(descendantPID),
            "timeout 후 TERM/HUP를 무시하는 후손 PID \(descendantPID)가 남으면 안 됩니다."
        )
    }

    func testRunProcessCancellationTerminatesSignalIgnoringDescendant() async throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descendantPIDURL = fixture.appendingPathComponent("descendant.pid")
        let script = signalIgnoringProcessTreeScript(pidFile: descendantPIDURL.path)

        let task = Task.detached {
            try GitRepositoryStatus.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script],
                currentDirectoryURL: fixture,
                timeout: 5
            )
        }
        XCTAssertTrue(waitForFile(descendantPIDURL))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소된 프로세스가 성공하면 안 됩니다.")
        } catch is CancellationError {
            let descendantPID = try readPID(from: descendantPIDURL)
            XCTAssertTrue(
                waitForProcessToExit(descendantPID),
                "취소 후 TERM/HUP를 무시하는 후손 PID \(descendantPID)가 남으면 안 됩니다."
            )
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }

    func testRunProcessBoundsCapturedStderrAndRedactsSensitiveURLParts() throws {
        let sensitiveURL = "https://alice:password@example.com/repo.git?api_key=api%2Dsecret&client_secret=client-secret&refresh_token=refresh-secret&oauth_token=oauth-secret&private_token=private-secret&X-Amz-Credential=aws-credential&X-Amz-Signature=aws-signature&ref=main"

        XCTAssertThrowsError(
            try GitRepositoryStatus.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "yes padding | head -c 1048576 >&2; printf '\\n%s\\n' '\(sensitiveURL)' >&2; exit 7",
                ],
                currentDirectoryURL: FileManager.default.temporaryDirectory,
                timeout: 5
            )
        ) { error in
            guard case GitRepositoryStatusError.commandFailed(let message) = error else {
                return XCTFail("예상하지 못한 오류: \(error)")
            }
            XCTAssertLessThanOrEqual(message.utf8.count, 262_500)
            XCTAssertFalse(message.contains("alice"))
            XCTAssertFalse(message.contains("password"))
            for secret in [
                "api%2Dsecret", "api-secret", "client-secret", "refresh-secret", "oauth-secret",
                "private-secret", "aws-credential", "aws-signature", "ref=main",
            ] {
                XCTAssertFalse(message.contains(secret), "URL query 값이 노출되었습니다: \(secret)")
            }
            XCTAssertTrue(message.contains("REDACTED"))
        }
    }

    func testRunProcessPreservesWorkingDirectoryEnvironmentAndStandardOutput() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        var environment = ProcessInfo.processInfo.environment
        environment["MARKAGENT_PROCESS_TEST"] = "expected-value"

        let output = try GitRepositoryStatus.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s|%s' \"$PWD\" \"$MARKAGENT_PROCESS_TEST\""],
            currentDirectoryURL: fixture,
            environment: environment,
            timeout: 2
        )

        let components = output.split(separator: "|", maxSplits: 1).map(String.init)
        XCTAssertEqual(components.count, 2)
        XCTAssertEqual(components.last, "expected-value")
        let workingDirectory = try XCTUnwrap(components.first)
        XCTAssertEqual(URL(fileURLWithPath: workingDirectory).lastPathComponent, fixture.lastPathComponent)
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryStatusTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    private func signalIgnoringProcessTreeScript(pidFile: String) -> String {
        """
        trap '' TERM HUP
        (trap '' TERM HUP; while :; do sleep 1; done) &
        child=$!
        printf '%d' "$child" > '\(pidFile)'
        wait "$child"
        """
    }

    private func readPID(from url: URL) throws -> pid_t {
        let value = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try XCTUnwrap(pid_t(value))
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func waitForProcessToExit(_ pid: pid_t, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) == -1, errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return kill(pid, 0) == -1 && errno == ESRCH
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

private final class BlockingRemoteFetcher: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func fetch() throws {
        lock.withLock { calls += 1 }
        release.wait()
        try Task.checkCancellation()
    }

    func finish() {
        release.signal()
    }
}

private final class BlockingBranchSnapshotLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private let branchName: String
    private var calls = 0

    init(branchName: String) {
        self.branchName = branchName
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func load() throws -> GitRepositoryStatus.BranchSnapshot {
        let call = lock.withLock {
            calls += 1
            return calls
        }
        if call > 1 {
            release.wait()
            try Task.checkCancellation()
        }
        return (branchName: branchName, local: [], remoteGroups: [])
    }

    func finishBlockedLoad() {
        release.signal()
    }
}

private final class SequencedBranchNameLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [String]
    private var index = 0

    init(values: [String]) {
        self.values = values
    }

    func load() -> String? {
        lock.withLock {
            let value = values[min(index, values.count - 1)]
            index += 1
            return value
        }
    }
}

private final class BlockingBranchNameLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let staleRelease = DispatchSemaphore(value: 0)
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }

    func load() -> String? {
        let call = lock.withLock {
            calls += 1
            return calls
        }
        switch call {
        case 1:
            return "initial-branch"
        case 2:
            staleRelease.wait()
            return "stale-branch"
        default:
            return "newest-branch"
        }
    }

    func finishStaleLoad() {
        staleRelease.signal()
    }
}

private final class BlockingCheckoutOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let firstRelease = DispatchSemaphore(value: 0)
    private let secondRelease = DispatchSemaphore(value: 0)
    private let firstRootPath: String
    private let secondRootPath: String
    private var firstStarted = false
    private var secondStarted = false

    init(firstRoot: URL, secondRoot: URL) {
        self.firstRootPath = firstRoot.standardizedFileURL.path
        self.secondRootPath = secondRoot.standardizedFileURL.path
    }

    var firstCallStarted: Bool { lock.withLock { firstStarted } }
    var secondCallStarted: Bool { lock.withLock { secondStarted } }

    func run(branch _: GitBranch, root: URL) throws {
        switch root.standardizedFileURL.path {
        case firstRootPath:
            lock.withLock { firstStarted = true }
            firstRelease.wait()
        case secondRootPath:
            lock.withLock { secondStarted = true }
            secondRelease.wait()
        default:
            XCTFail("예상하지 못한 checkout root: \(root.path)")
        }
    }

    func finishFirst() { firstRelease.signal() }
    func finishSecond() { secondRelease.signal() }
}

private final class BlockingRepositoryInitializer: @unchecked Sendable {
    private let lock = NSLock()
    private let firstRelease = DispatchSemaphore(value: 0)
    private let secondRelease = DispatchSemaphore(value: 0)
    private let firstDirectoryPath: String
    private let secondDirectoryPath: String
    private var firstStarted = false
    private var secondStarted = false

    init(firstDirectory: URL, secondDirectory: URL) {
        self.firstDirectoryPath = firstDirectory.standardizedFileURL.path
        self.secondDirectoryPath = secondDirectory.standardizedFileURL.path
    }

    var firstCallStarted: Bool { lock.withLock { firstStarted } }
    var secondCallStarted: Bool { lock.withLock { secondStarted } }

    func run(directory: URL) throws {
        switch directory.standardizedFileURL.path {
        case firstDirectoryPath:
            lock.withLock { firstStarted = true }
            firstRelease.wait()
        case secondDirectoryPath:
            lock.withLock { secondStarted = true }
            secondRelease.wait()
        default:
            XCTFail("예상하지 못한 init directory: \(directory.path)")
        }
    }

    func finishFirst() { firstRelease.signal() }
    func finishSecond() { secondRelease.signal() }
}

private final class CheckoutCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }

    func record(branch _: GitBranch, root _: URL) {
        lock.withLock { calls += 1 }
    }
}
