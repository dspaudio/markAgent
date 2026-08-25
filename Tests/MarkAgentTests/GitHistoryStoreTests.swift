import Foundation
import XCTest
@testable import ma

@MainActor
final class GitHistoryStoreTests: XCTestCase {
    func testRefreshBuildsExactBoundedGitLogRequestWithoutZ() async throws {
        let root = URL(fileURLWithPath: "/tmp/history repository")
        let runner = RecordingHistoryRunner(result: .success(.init(stdout: Data(), stderr: Data())))
        let store = GitHistoryStore(commandRunner: { request in try await runner.run(request) })

        await store.refresh(repositoryRoot: root)

        let request = try XCTUnwrap(runner.requests.first)
        XCTAssertEqual(request.executableURL, URL(fileURLWithPath: "/usr/bin/git"))
        XCTAssertEqual(request.arguments, [
            "-C", root.path,
            "log", "--all", "--max-count=100", "--date=iso-strict",
            "--pretty=format:%H%x00%h%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00",
        ])
        XCTAssertFalse(request.arguments.contains("-z"))
        XCTAssertEqual(request.timeoutSeconds, 5)
        XCTAssertEqual(request.outputByteLimit, 4_194_304)
    }

    func testParsesOneRecordIncludingAnEmptyBody() async {
        let commit = fixtureCommit(hash: "a", shortHash: "aaaaaaa", subject: "initial", body: "")
        let store = makeStore(stdout: record(commit))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.commits.count, 1)
        XCTAssertEqual(store.commits.first?.id, String(repeating: "a", count: 40))
        XCTAssertEqual(store.commits.first?.shortHash, "aaaaaaa")
        XCTAssertEqual(store.commits.first?.authorName, "Ada Lovelace")
        XCTAssertEqual(store.commits.first?.authorEmail, "ada@example.com")
        XCTAssertEqual(store.commits.first?.subject, "initial")
        XCTAssertEqual(store.commits.first?.body, "")
    }

    func testParsesSHA256ObjectID() async {
        let hash = String(repeating: "a", count: 64)
        let commit = fixtureCommit(
            hash: hash,
            shortHash: "aaaaaaaaaaaa",
            subject: "sha256",
            body: ""
        )
        let store = makeStore(stdout: record(commit))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.commits.first?.id, hash)
        XCTAssertEqual(store.commits.first?.shortHash, "aaaaaaaaaaaa")
    }

    func testParsesMultipleRecordsInGitOutputOrderAndStripsOnlyInterRecordLF() async {
        let newest = fixtureCommit(hash: "b", shortHash: "bbbbbbb", subject: "newest", body: "first line\nsecond line\n")
        let oldest = fixtureCommit(hash: "c", shortHash: "ccccccc", subject: "oldest", body: "\nbody begins with LF\n")
        let store = makeStore(stdout: record(newest) + Data("\n".utf8) + record(oldest))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.commits.map(\.id), [
            String(repeating: "b", count: 40),
            String(repeating: "c", count: 40),
        ])
        XCTAssertEqual(store.commits.map(\.subject), ["newest", "oldest"])
        XCTAssertEqual(store.commits.first?.body, "first line\nsecond line\n")
        XCTAssertEqual(store.commits.last?.body, "\nbody begins with LF\n")
    }

    func testInvalidHashFailsWholeResponse() async {
        let malformed = fixtureCommit(hash: "not-a-hash", shortHash: "broken", subject: "subject", body: "body")
        let store = makeStore(stdout: record(malformed))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .failed(.invalidHash("not-a-hash")))
        XCTAssertTrue(store.commits.isEmpty)
    }

    func testInvalidFieldArityFailsWholeResponse() async {
        let fields = [String](repeating: "field", count: 6).joined(separator: "\u{0}") + "\u{0}"
        let store = makeStore(stdout: Data(fields.utf8))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .failed(.malformedRecord))
        XCTAssertTrue(store.commits.isEmpty)
    }

    func testInvalidUTF8FailsWholeResponse() async {
        let store = makeStore(stdout: Data([0xFF, 0x00]))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .failed(.invalidUTF8))
        XCTAssertTrue(store.commits.isEmpty)
    }

    func testInvalidAuthoredDateFailsWholeResponse() async {
        let malformed = fixtureCommit(hash: "d", shortHash: "ddddddd", subject: "subject", body: "body", authoredAt: "not-an-iso-date")
        let store = makeStore(stdout: record(malformed))

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .failed(.invalidDate("not-an-iso-date")))
        XCTAssertTrue(store.commits.isEmpty)
    }

    func testNilRepositorySkipsRunnerAndPublishesNoRepository() async {
        let runner = RecordingHistoryRunner(result: .success(.init(stdout: Data(), stderr: Data())))
        let store = GitHistoryStore(commandRunner: { request in try await runner.run(request) })

        await store.refresh(repositoryRoot: nil)

        XCTAssertEqual(runner.requests.count, 0)
        XCTAssertEqual(store.state, .noRepository)
        XCTAssertTrue(store.commits.isEmpty)
        XCTAssertNil(store.selectedCommit)
    }

    func testEmptyOutputPublishesLoadedEmptyState() async {
        let store = makeStore(stdout: Data())

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .loaded)
        XCTAssertTrue(store.commits.isEmpty)
        XCTAssertNil(store.selectedCommit)
    }

    func testRefreshParsesOutputOffMainThread() async {
        let probe = ParserThreadProbe()
        let runner = RecordingHistoryRunner(
            result: .success(.init(stdout: Data(), stderr: Data()))
        )
        let store = GitHistoryStore(
            commandRunner: { request in try await runner.run(request) },
            parser: { _ in
                probe.recordCurrentThread()
                return []
            }
        )

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(probe.ranOnMainThread, false)
        XCTAssertEqual(store.state, .loaded)
    }

    func testRunnerFailurePublishesStructuredError() async {
        let failure = GitHistoryRunnerFailure.nonZeroExit(exitCode: 17, stderr: Data("fatal: broken".utf8))
        let runner = RecordingHistoryRunner(result: .failure(failure))
        let store = GitHistoryStore(commandRunner: { request in try await runner.run(request) })

        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.state, .failed(.runner(failure)))
        XCTAssertTrue(store.commits.isEmpty)
    }

    func testRefreshPreservesSelectedCommitWhenItRemainsInNewResult() async {
        let first = fixtureCommit(hash: "e", shortHash: "eeeeeee", subject: "first", body: "")
        let retained = fixtureCommit(hash: "f", shortHash: "fffffff", subject: "retained", body: "")
        let replacement = fixtureCommit(hash: "1", shortHash: "1111111", subject: "replacement", body: "")
        let runner = SequencedHistoryRunner(outputs: [
            record(first) + Data("\n".utf8) + record(retained),
            record(replacement) + Data("\n".utf8) + record(retained),
        ])
        let store = GitHistoryStore(commandRunner: { request in try await runner.run(request) })

        await store.refresh(repositoryRoot: fixtureRoot)
        store.selectCommit(id: String(repeating: "f", count: 40))
        await store.refresh(repositoryRoot: fixtureRoot)

        XCTAssertEqual(store.selectedCommit?.id, String(repeating: "f", count: 40))
        XCTAssertEqual(store.selectedCommit?.subject, "retained")
    }

    func testNewerGenerationSuppressesStaleResult() async throws {
        let staleStarted = expectation(description: "stale refresh started")
        let currentStarted = expectation(description: "current refresh started")
        let runner = SuspendedHistoryRunner(started: [staleStarted, currentStarted])
        let store = GitHistoryStore(commandRunner: { request in try await runner.run(request) })
        let stale = Task { @MainActor in await store.refresh(repositoryRoot: self.fixtureRoot) }

        await fulfillment(of: [staleStarted], timeout: 1)
        let current = Task { @MainActor in await store.refresh(repositoryRoot: self.fixtureRoot) }
        await fulfillment(of: [currentStarted], timeout: 1)

        await runner.complete(call: 1, with: .success(.init(stdout: record(fixtureCommit(hash: "2", shortHash: "2222222", subject: "current", body: "")), stderr: Data())))
        await current.value
        await runner.complete(call: 0, with: .success(.init(stdout: record(fixtureCommit(hash: "3", shortHash: "3333333", subject: "stale", body: "")), stderr: Data())))
        await stale.value

        XCTAssertEqual(store.commits.map(\.subject), ["current"])
        XCTAssertEqual(store.state, .loaded)
    }

    func testRepositoryChangeSuppressesOldRootResult() async throws {
        let firstStarted = expectation(description: "first root refresh started")
        let secondStarted = expectation(description: "second root refresh started")
        let runner = SuspendedHistoryRunner(started: [firstStarted, secondStarted])
        let store = GitHistoryStore(commandRunner: { request in try await runner.run(request) })
        let firstRoot = URL(fileURLWithPath: "/tmp/git-history-first")
        let secondRoot = URL(fileURLWithPath: "/tmp/git-history-second")
        let first = Task { @MainActor in await store.refresh(repositoryRoot: firstRoot) }

        await fulfillment(of: [firstStarted], timeout: 1)
        let second = Task { @MainActor in await store.refresh(repositoryRoot: secondRoot) }
        await fulfillment(of: [secondStarted], timeout: 1)

        await runner.complete(call: 1, with: .success(.init(stdout: record(fixtureCommit(hash: "4", shortHash: "4444444", subject: "second root", body: "")), stderr: Data())))
        await second.value
        await runner.complete(call: 0, with: .success(.init(stdout: record(fixtureCommit(hash: "5", shortHash: "5555555", subject: "first root", body: "")), stderr: Data())))
        await first.value

        XCTAssertEqual(store.commits.map(\.subject), ["second root"])
        XCTAssertEqual(store.state, .loaded)
    }

    private let fixtureRoot = URL(fileURLWithPath: "/tmp/git-history-fixture")

    private func makeStore(stdout: Data) -> GitHistoryStore {
        let runner = RecordingHistoryRunner(result: .success(.init(stdout: stdout, stderr: Data())))
        return GitHistoryStore(commandRunner: { request in try await runner.run(request) })
    }

    private func fixtureCommit(
        hash: String,
        shortHash: String,
        subject: String,
        body: String,
        authoredAt: String = "2025-01-02T03:04:05+00:00"
    ) -> [String] {
        [
            String(repeating: hash, count: hash.count == 1 ? 40 : 1),
            shortHash,
            "Ada Lovelace",
            "ada@example.com",
            authoredAt,
            subject,
            body,
        ]
    }

    private func record(_ fields: [String]) -> Data {
        Data((fields.joined(separator: "\u{0}") + "\u{0}").utf8)
    }
}

private final class RecordingHistoryRunner: @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<GitHistoryRawOutput, GitHistoryRunnerFailure>
    private var recordedRequests: [GitHistoryProcessRequest] = []

    init(result: Result<GitHistoryRawOutput, GitHistoryRunnerFailure>) {
        self.result = result
    }

    var requests: [GitHistoryProcessRequest] {
        lock.withLock { recordedRequests }
    }

    func run(_ request: GitHistoryProcessRequest) async throws -> GitHistoryRawOutput {
        lock.withLock { recordedRequests.append(request) }
        return try result.get()
    }
}

private final class SequencedHistoryRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [Data]

    init(outputs: [Data]) {
        self.outputs = outputs
    }

    func run(_: GitHistoryProcessRequest) async throws -> GitHistoryRawOutput {
        let output = lock.withLock { outputs.removeFirst() }
        return .init(stdout: output, stderr: Data())
    }
}

private final class ParserThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValue: Bool?

    var ranOnMainThread: Bool? {
        lock.withLock { recordedValue }
    }

    func recordCurrentThread() {
        lock.withLock { recordedValue = Thread.isMainThread }
    }
}

private actor SuspendedHistoryRunner {
    private let started: [XCTestExpectation]
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<GitHistoryRawOutput, Error>] = [:]

    init(started: [XCTestExpectation]) {
        self.started = started
    }

    func run(_: GitHistoryProcessRequest) async throws -> GitHistoryRawOutput {
        let call = nextCall
        nextCall += 1
        started[call].fulfill()
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func complete(call: Int, with result: Result<GitHistoryRawOutput, Error>) {
        let continuation = continuations.removeValue(forKey: call)
        switch result {
        case .success(let output):
            continuation?.resume(returning: output)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}
