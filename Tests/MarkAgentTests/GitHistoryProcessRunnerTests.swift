import Darwin
import Foundation
import XCTest
@testable import ma

final class GitHistoryProcessRunnerTests: XCTestCase {
    func testReadFailureCompletionStateTreatsFailedStreamAsTerminal() {
        var state = GitHistoryPipeCompletionState()

        state.markStdoutEnded()

        XCTAssertTrue(state.stdoutEnded)
        XCTAssertFalse(state.stderrEnded)
        XCTAssertFalse(state.isComplete)

        state.markStderrEnded()

        XCTAssertTrue(state.isComplete)
    }

    @MainActor
    func testChildIsItsOwnProcessGroupLeader() async throws {
        let output = try await awaitRunnerResult(
            Self.request(script: "printf '%s:' \"$$\"; /usr/bin/perl -MPOSIX=getpgrp -e 'print getpgrp'"),
            named: "process group observation"
        ).get()
        let values = try XCTUnwrap(String(data: output.stdout, encoding: .utf8))
            .split(separator: ":", maxSplits: 1)
            .map { try XCTUnwrap(Int32($0)) }

        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0], values[1], "The helper shell's getpgrp() must equal its pid.")
    }

    @MainActor
    func testDrainsStdoutAndStderrConcurrently() async throws {
        let output = try await awaitRunnerResult(
            Self.request(script: "(/usr/bin/perl -e 'print \"stdout\\n\"; print \"o\" x 262137') & first=$!; (/usr/bin/perl -e 'print \"stderr\\n\"; print \"e\" x 262137' >&2) & second=$!; wait \"$first\" \"$second\""),
            named: "concurrent drain completion"
        ).get()

        XCTAssertEqual(output.stdout.count, 262_144)
        XCTAssertEqual(output.stderr.count, 262_144)
        XCTAssertTrue(output.stdout.starts(with: Data("stdout\n".utf8)))
        XCTAssertTrue(output.stderr.starts(with: Data("stderr\n".utf8)))
    }

    @MainActor
    func testChildEnvironmentExcludesParentHomeAndGitOverrides() async throws {
        let request = GitHistoryProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            timeoutSeconds: 5,
            outputByteLimit: 4_194_304
        )
        let output = try await awaitRunnerResult(
            request,
            named: "sanitized child environment"
        ).get()
        let environment = try XCTUnwrap(String(data: output.stdout, encoding: .utf8))
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let keys = Set(environment.compactMap { line in
            line.split(separator: "=", maxSplits: 1).first.map(String.init)
        })
        XCTAssertEqual(keys, ["PATH", "LC_ALL"])
        XCTAssertEqual(
            environment.first { $0.hasPrefix("PATH=") },
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        )
        XCTAssertEqual(
            environment.first { $0.hasPrefix("LC_ALL=") },
            "LC_ALL=en_US.UTF-8"
        )
    }

    @MainActor
    func testSpawnClosesUnrelatedParentDescriptors() async throws {
        let descriptor = open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let output = try await awaitRunnerResult(
            Self.request(
                script: "if [ -e /dev/fd/\(descriptor) ]; then printf inherited; else printf closed; fi"
            ),
            named: "parent descriptor isolation"
        ).get()

        XCTAssertEqual(output.stdout, Data("closed".utf8))
    }

    @MainActor
    func testNonzeroExitPreservesStructuredStderr() async {
        let result = await awaitRunnerResult(
            Self.request(script: "printf 'ordinary output'; printf 'structured diagnostic' >&2; exit 23"),
            named: "nonzero completion"
        )

        XCTAssertEqual(
            result,
            .failure(.nonZeroExit(exitCode: 23, stderr: Data("structured diagnostic".utf8)))
        )
    }

    @MainActor
    func testCombinedOutputOverFourMiBIsRejected() async {
        let result = await awaitRunnerResult(
            Self.request(script: "(yes stdout | head -c 2097153) & first=$!; (yes stderr | head -c 2097152 >&2) & second=$!; wait \"$first\" \"$second\""),
            named: "output ceiling completion"
        )

        XCTAssertEqual(result, .failure(.outputLimitExceeded(limit: 4_194_304)))
    }

    @MainActor
    func testCancellationTerminatesEntireProcessGroupAndCompletesCleanupBeforeReturning() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let writeObserved = try observeWrite(to: fixture.pidFile, expectation: expectation(description: "signal-ignoring descendant started"))
        defer { writeObserved.cancel() }
        let completion = expectation(description: "cancelled runner completed")
        let result = RunnerResultBox()
        let processRequest = Self.request(script: Self.signalIgnoringTree(pidFile: fixture.pidFile.path))
        let task = Task { @MainActor in
            result.store(await Self.runnerResult(processRequest))
            completion.fulfill()
        }

        await fulfillment(of: [writeObserved.expectation], timeout: 1)
        task.cancel()
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(result.value, .failure(.cancelled))
        XCTAssertTrue(processDoesNotExist(try readPID(from: fixture.pidFile)))
    }

    @MainActor
    func testControlledTimeoutTerminatesEntireProcessGroupAndCompletesCleanupBeforeReturning() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let writeObserved = try observeWrite(to: fixture.pidFile, expectation: expectation(description: "timeout descendant started"))
        defer { writeObserved.cancel() }
        let deadline = ControlledDeadline()
        let deadlineWait: @Sendable () async -> Void = { await deadline.wait() }
        let completion = expectation(description: "timed-out runner completed")
        let result = RunnerResultBox()
        let processRequest = Self.request(script: Self.signalIgnoringTree(pidFile: fixture.pidFile.path))

        Task { @MainActor in
            // Builder contract: this overload is the only deadline seam. The default run(_:) uses ContinuousClock and the request's five-second timeout.
            result.store(await Self.runnerResult(processRequest, deadline: deadlineWait))
            completion.fulfill()
        }

        await fulfillment(of: [writeObserved.expectation], timeout: 1)
        await deadline.fire()
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(result.value, .failure(.timedOut(seconds: 5)))
        XCTAssertTrue(processDoesNotExist(try readPID(from: fixture.pidFile)))
    }

    @MainActor
    func testTimeoutTerminatesDescendantAfterProcessGroupLeaderExits() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let leaderExitedFile = fixture.directory.appendingPathComponent("leader-exited")
        let releaseFile = fixture.directory.appendingPathComponent("release-descendant")
        FileManager.default.createFile(atPath: leaderExitedFile.path, contents: Data())
        let leaderExitObserved = try observeWrite(
            to: leaderExitedFile,
            expectation: expectation(description: "descendant observed the reaped group leader")
        )
        defer { leaderExitObserved.cancel() }
        let deadline = ControlledDeadline()
        let deadlineWait: @Sendable () async -> Void = { await deadline.wait() }
        let completion = expectation(description: "timed-out runner completed after leader exit")
        let cleanupCompletion = expectation(description: "runner cleanup completed after fixture release")
        let result = RunnerResultBox()
        let processRequest = Self.request(
            script: Self.descendantHoldingPipesAfterLeaderExit(
                pidFile: fixture.pidFile.path,
                leaderExitedFile: leaderExitedFile.path,
                releaseFile: releaseFile.path
            )
        )

        Task { @MainActor in
            result.store(await Self.runnerResult(processRequest, deadline: deadlineWait))
            completion.fulfill()
            cleanupCompletion.fulfill()
        }

        await fulfillment(of: [leaderExitObserved.expectation], timeout: 1)
        await deadline.fire()
        await fulfillment(of: [completion], timeout: 1)
        FileManager.default.createFile(atPath: releaseFile.path, contents: Data())
        await fulfillment(of: [cleanupCompletion], timeout: 1)

        XCTAssertEqual(result.value, .failure(.timedOut(seconds: 5)))
        XCTAssertTrue(processDoesNotExist(try readPID(from: fixture.pidFile)))
    }

    @MainActor
    func testNonzeroLeaderExitTerminatesDescendantAndPreservesStderr() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let leaderReadyFile = fixture.directory.appendingPathComponent("leader-ready")
        let releaseFile = fixture.directory.appendingPathComponent("release-descendant")
        FileManager.default.createFile(atPath: leaderReadyFile.path, contents: Data())
        let leaderReadyObserved = try observeWrite(
            to: leaderReadyFile,
            expectation: expectation(description: "nonzero leader spawned descendant")
        )
        defer { leaderReadyObserved.cancel() }
        let completion = expectation(description: "nonzero runner terminated descendant")
        let cleanupCompletion = expectation(description: "nonzero runner cleanup completed")
        let result = RunnerResultBox()
        let processRequest = Self.request(
            script: Self.descendantHoldingPipesAfterNonzeroLeaderExit(
                pidFile: fixture.pidFile.path,
                leaderReadyFile: leaderReadyFile.path,
                releaseFile: releaseFile.path
            )
        )

        Task { @MainActor in
            result.store(await Self.runnerResult(processRequest))
            completion.fulfill()
            cleanupCompletion.fulfill()
        }

        await fulfillment(of: [leaderReadyObserved.expectation], timeout: 1)
        await fulfillment(of: [completion], timeout: 1)
        XCTAssertTrue(
            processDoesNotExist(try readPID(from: fixture.pidFile)),
            "Nonzero leader exit must kill the descendant before deadline fallback."
        )
        FileManager.default.createFile(atPath: releaseFile.path, contents: Data())
        await fulfillment(of: [cleanupCompletion], timeout: 1)

        XCTAssertEqual(
            result.value,
            .failure(
                .nonZeroExit(
                    exitCode: 7,
                    stderr: Data(repeating: 0x65, count: 1_048_576)
                )
            )
        )
        XCTAssertTrue(processDoesNotExist(try readPID(from: fixture.pidFile)))
    }

    private static func request(script: String) -> GitHistoryProcessRequest {
        .init(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeoutSeconds: 5,
            outputByteLimit: 4_194_304
        )
    }

    @MainActor
    private func awaitRunnerResult(
        _ request: GitHistoryProcessRequest,
        named name: String
    ) async -> Result<GitHistoryRawOutput, GitHistoryRunnerFailure> {
        let completed = expectation(description: name)
        let result = RunnerResultBox()
        Task { @MainActor in
            result.store(await Self.runnerResult(request))
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2)
        return result.value
    }

    private static func runnerResult(
        _ request: GitHistoryProcessRequest,
        deadline: (@Sendable () async -> Void)? = nil
    ) async -> Result<GitHistoryRawOutput, GitHistoryRunnerFailure> {
        do {
            let output: GitHistoryRawOutput
            if let deadline {
                output = try await GitHistoryProcessRunner.run(request, deadline: deadline)
            } else {
                output = try await GitHistoryProcessRunner.run(request)
            }
            return .success(output)
        } catch let failure as GitHistoryRunnerFailure {
            return .failure(failure)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            XCTFail("Unexpected runner failure: \(error)")
            return .failure(.launchFailed(String(describing: error)))
        }
    }

    private func makeFixture() throws -> (directory: URL, pidFile: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitHistoryProcessRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pidFile = directory.appendingPathComponent("descendant.pid")
        FileManager.default.createFile(atPath: pidFile.path, contents: Data())
        return (directory, pidFile)
    }

    private static func signalIgnoringTree(pidFile: String) -> String {
        """
        trap '' TERM HUP
        (trap '' TERM HUP; while :; do :; done) &
        child=$!
        printf '%d' "$child" > '\(pidFile)'
        wait "$child"
        """
    }

    private static func descendantHoldingPipesAfterLeaderExit(
        pidFile: String,
        leaderExitedFile: String,
        releaseFile: String
    ) -> String {
        """
        parent=$$
        /bin/sh -c '
            trap "" TERM HUP
            while kill -0 "$1" 2>/dev/null; do :; done
            printf observed > "$2"
            while [ ! -e "$3" ]; do :; done
        ' descendant "$parent" '\(leaderExitedFile)' '\(releaseFile)' &
        child=$!
        printf '%d' "$child" > '\(pidFile)'
        exit 0
        """
    }

    private static func descendantHoldingPipesAfterNonzeroLeaderExit(
        pidFile: String,
        leaderReadyFile: String,
        releaseFile: String
    ) -> String {
        """
        exec /usr/bin/perl -MPOSIX -e '
            my ($pid_file, $ready_file, $release_file) = @ARGV;
            my $child = fork();
            die "fork failed" unless defined $child;
            if ($child == 0) {
                $SIG{TERM} = "IGNORE";
                $SIG{HUP} = "IGNORE";
                while (!-e $release_file) {}
                POSIX::_exit(0);
            }
            open(my $child_fh, ">", $pid_file) or die $!;
            print $child_fh $child;
            close($child_fh);
            open(my $ready_fh, ">", $ready_file) or die $!;
            print $ready_fh "ready";
            close($ready_fh);
            print STDERR "e" x 1048576;
            POSIX::_exit(7);
        ' '\(pidFile)' '\(leaderReadyFile)' '\(releaseFile)'
        """
    }

    private func readPID(from url: URL) throws -> pid_t {
        let value = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try XCTUnwrap(pid_t(value))
    }

    private func processDoesNotExist(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    private func observeWrite(to url: URL, expectation: XCTestExpectation) throws -> WriteObservation {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .global()
        )
        source.setEventHandler(handler: expectation.fulfill)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return WriteObservation(expectation: expectation, source: source)
    }
}

private final class RunnerResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Result<GitHistoryRawOutput, GitHistoryRunnerFailure>?

    var value: Result<GitHistoryRawOutput, GitHistoryRunnerFailure> {
        lock.withLock { storedValue! }
    }

    var optionalValue: Result<GitHistoryRawOutput, GitHistoryRunnerFailure>? {
        lock.withLock { storedValue }
    }

    func store(_ result: Result<GitHistoryRawOutput, GitHistoryRunnerFailure>) {
        lock.withLock { storedValue = result }
    }
}

private final class WriteObservation {
    let expectation: XCTestExpectation
    private let source: DispatchSourceFileSystemObject

    init(expectation: XCTestExpectation, source: DispatchSourceFileSystemObject) {
        self.expectation = expectation
        self.source = source
    }

    func cancel() {
        source.cancel()
    }
}

private actor ControlledDeadline {
    private var hasFired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !hasFired else { return }
        await withCheckedContinuation { continuation in
            if self.hasFired {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func fire() {
        guard !hasFired else { return }
        hasFired = true
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
