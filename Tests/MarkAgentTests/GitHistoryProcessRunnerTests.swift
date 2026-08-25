import Darwin
import Foundation
import XCTest
@testable import ma

final class GitHistoryProcessRunnerTests: XCTestCase {
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
