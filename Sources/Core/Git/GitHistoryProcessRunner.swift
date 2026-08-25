import Darwin
import Foundation

struct GitHistoryRawOutput: Equatable, Sendable {
    let stdout: Data
    let stderr: Data
}

enum GitHistoryRunnerFailure: Error, Equatable, Sendable {
    case launchFailed(String)
    case processGroupFailed(errno: Int32)
    case nonZeroExit(exitCode: Int32, stderr: Data)
    case timedOut(seconds: Int)
    case outputLimitExceeded(limit: Int)
    case stdoutReadFailed(errno: Int32)
    case stderrReadFailed(errno: Int32)
    case cancelled
}

struct GitHistoryProcessRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let timeoutSeconds: Int
    let outputByteLimit: Int
}

typealias GitHistoryCommandRunner = @Sendable (GitHistoryProcessRequest) async throws -> GitHistoryRawOutput

struct GitHistoryPipeCompletionState: Equatable, Sendable {
    private(set) var stdoutEnded = false
    private(set) var stderrEnded = false

    var isComplete: Bool { stdoutEnded && stderrEnded }

    mutating func markStdoutEnded() {
        stdoutEnded = true
    }

    mutating func markStderrEnded() {
        stderrEnded = true
    }
}

struct GitHistoryProcessRunner: Sendable {
    static nonisolated func run(_ request: GitHistoryProcessRequest) async throws -> GitHistoryRawOutput {
        let seconds = request.timeoutSeconds
        return try await run(request) {
            let clock = ContinuousClock()
            try? await clock.sleep(until: clock.now.advanced(by: .seconds(seconds)))
        }
    }

    static nonisolated func run(
        _ request: GitHistoryProcessRequest,
        deadline: @escaping @Sendable () async -> Void
    ) async throws -> GitHistoryRawOutput {
        let process = try spawn(request)
        defer { process.output.closeAll() }

        let processGroup = ProcessGroupToken(pid: process.pid)
        let cancellation = CancellationSignal()
        let budget = CombinedOutputBudget(limit: request.outputByteLimit)

        return try await withTaskCancellationHandler {
            try await collect(
                process: process,
                request: request,
                deadline: deadline,
                processGroup: processGroup,
                cancellation: cancellation,
                budget: budget
            )
        } onCancel: {
            processGroup.terminate()
            cancellation.signal()
        }
    }

    private struct SpawnedProcess: Sendable {
        let pid: pid_t
        let output: OutputDescriptorToken
    }

    fileprivate enum Stream: Sendable {
        case stdout
        case stderr
    }

    fileprivate enum Event: Sendable {
        case chunk(Stream, Data)
        case idle(Stream)
        case end(Stream)
        case readFailure(Stream, Int32)
        case outputLimitExceeded(Stream)
        case exited(Int32)
        case deadline
        case cancelled
        case escalate
    }

    private static nonisolated func collect(
        process: SpawnedProcess,
        request: GitHistoryProcessRequest,
        deadline: @escaping @Sendable () async -> Void,
        processGroup: ProcessGroupToken,
        cancellation: CancellationSignal,
        budget: CombinedOutputBudget
    ) async throws -> GitHistoryRawOutput {
        var stdout = Data()
        var stderr = Data()
        var pipeCompletion = GitHistoryPipeCompletionState()
        var waitStatus: Int32?
        var failure: GitHistoryRunnerFailure?
        var escalationScheduled = false

        return try await withThrowingTaskGroup(of: Event.self) { group in
            group.addTask { read(process.output.stdout, output: process.output, stream: .stdout, budget: budget, enforceLimit: true) }
            group.addTask { read(process.output.stderr, output: process.output, stream: .stderr, budget: budget, enforceLimit: true) }
            group.addTask { waitForExit(process.pid) }
            group.addTask {
                await deadline()
                return Task.isCancelled ? .cancelled : .deadline
            }
            group.addTask { await cancellation.wait() }

            while let event = try await group.next() {
                switch event {
                case .chunk(let stream, let data):
                    if failure == nil {
                        switch stream {
                        case .stdout: stdout.append(data)
                        case .stderr: stderr.append(data)
                        }
                    }
                    let shouldEnforceLimit = failure == nil
                    switch stream {
                    case .stdout:
                        group.addTask {
                            read(process.output.stdout, output: process.output, stream: .stdout, budget: budget, enforceLimit: shouldEnforceLimit)
                        }
                    case .stderr:
                        group.addTask {
                            read(process.output.stderr, output: process.output, stream: .stderr, budget: budget, enforceLimit: shouldEnforceLimit)
                        }
                    }

                case .idle(let stream):
                    let shouldEnforceLimit = failure == nil
                    switch stream {
                    case .stdout where !pipeCompletion.stdoutEnded:
                        group.addTask {
                            read(process.output.stdout, output: process.output, stream: .stdout, budget: budget, enforceLimit: shouldEnforceLimit)
                        }
                    case .stderr where !pipeCompletion.stderrEnded:
                        group.addTask {
                            read(process.output.stderr, output: process.output, stream: .stderr, budget: budget, enforceLimit: shouldEnforceLimit)
                        }
                    default:
                        break
                    }

                case .end(.stdout):
                    pipeCompletion.markStdoutEnded()
                case .end(.stderr):
                    pipeCompletion.markStderrEnded()

                case .readFailure(let stream, let errorNumber):
                    switch stream {
                    case .stdout: pipeCompletion.markStdoutEnded()
                    case .stderr: pipeCompletion.markStderrEnded()
                    }
                    let hasNonzeroExit = waitStatus.map { decodedExitCode($0) != 0 } == true
                    if failure == nil, !hasNonzeroExit {
                        switch stream {
                        case .stdout: failure = .stdoutReadFailed(errno: errorNumber)
                        case .stderr: failure = .stderrReadFailed(errno: errorNumber)
                        }
                        processGroup.terminate()
                    }

                case .outputLimitExceeded(let stream):
                    if failure == nil {
                        failure = .outputLimitExceeded(limit: request.outputByteLimit)
                        processGroup.terminate()
                    }
                    switch stream {
                    case .stdout where !pipeCompletion.stdoutEnded:
                        group.addTask { read(process.output.stdout, output: process.output, stream: .stdout, budget: budget, enforceLimit: false) }
                    case .stderr where !pipeCompletion.stderrEnded:
                        group.addTask { read(process.output.stderr, output: process.output, stream: .stderr, budget: budget, enforceLimit: false) }
                    default:
                        break
                    }

                case .exited(let status):
                    waitStatus = status
                    if decodedExitCode(status) != 0 {
                        processGroup.terminate()
                        processGroup.killNow()
                    }

                case .deadline:
                    if failure == nil {
                        failure = .timedOut(seconds: request.timeoutSeconds)
                        processGroup.terminate()
                    }

                case .cancelled:
                    if failure == nil, Task.isCancelled || cancellation.wasSignalled {
                        failure = .cancelled
                        processGroup.terminate()
                    }

                case .escalate:
                    processGroup.killNow()
                }

                let requiresEscalation = failure != nil
                if requiresEscalation, !escalationScheduled {
                    escalationScheduled = true
                    group.addTask {
                        await terminationGraceDeadline()
                        return .escalate
                    }
                }

                if waitStatus != nil, pipeCompletion.isComplete {
                    cancellation.finish()
                    group.cancelAll()
                    while try await group.next() != nil {}
                    break
                }
            }

            if let failure { throw failure }
            guard let waitStatus else {
                throw GitHistoryRunnerFailure.launchFailed("waitpid did not report child completion")
            }
            let exitCode = decodedExitCode(waitStatus)
            guard exitCode == 0 else {
                throw GitHistoryRunnerFailure.nonZeroExit(exitCode: exitCode, stderr: stderr)
            }
            return GitHistoryRawOutput(stdout: stdout, stderr: stderr)
        }
    }

    private static nonisolated func read(
        _ descriptor: Int32,
        output: OutputDescriptorToken,
        stream: Stream,
        budget: CombinedOutputBudget,
        enforceLimit: Bool
    ) -> Event {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            var descriptorState = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let readiness = Darwin.poll(&descriptorState, 1, 100)
            if readiness == -1 {
                if errno == EINTR { continue }
                return .readFailure(stream, errno)
            }
            if readiness == 0 {
                return output.isClosed ? .end(stream) : .idle(stream)
            }

            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count > 0 {
                let data = Data(bytes.prefix(Int(count)))
                if enforceLimit, !budget.reserve(data.count) {
                    return .outputLimitExceeded(stream)
                }
                return .chunk(stream, data)
            }
            if count == 0 { return .end(stream) }
            if errno == EINTR { continue }
            return .readFailure(stream, errno)
        }
    }

    private static nonisolated func waitForExit(_ pid: pid_t) -> Event {
        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, 0)
            if result == pid {
                if decodedExitCode(status) != 0 {
                    _ = Darwin.kill(-pid, SIGTERM)
                    _ = Darwin.kill(-pid, SIGKILL)
                }
                return .exited(status)
            }
            if result == -1, errno == EINTR { continue }
            return .exited(127 << 8)
        }
    }

    private static nonisolated func terminationGraceDeadline() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
                continuation.resume()
            }
        }
    }

    private static nonisolated func decodedExitCode(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private static nonisolated func spawn(_ request: GitHistoryProcessRequest) throws -> SpawnedProcess {
        var stdoutPipe = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&stdoutPipe) == 0 else { throw launchFailure(errno) }

        var stderrPipe = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&stderrPipe) == 0 else {
            stdoutPipe.forEach { Darwin.close($0) }
            throw launchFailure(errno)
        }

        var ownsDescriptors = true
        defer {
            if ownsDescriptors {
                (stdoutPipe + stderrPipe).filter { $0 >= 0 }.forEach { Darwin.close($0) }
            }
        }

        var actions: posix_spawn_file_actions_t?
        var result = posix_spawn_file_actions_init(&actions)
        guard result == 0 else { throw launchFailure(result) }
        defer { posix_spawn_file_actions_destroy(&actions) }

        let actionResults = [
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO),
            posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]),
            posix_spawn_file_actions_addclose(&actions, stderrPipe[0]),
            posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]),
            posix_spawn_file_actions_addclose(&actions, stderrPipe[1]),
        ]
        if let failure = actionResults.first(where: { $0 != 0 }) {
            throw launchFailure(failure)
        }

        var attributes: posix_spawnattr_t?
        result = posix_spawnattr_init(&attributes)
        guard result == 0 else { throw launchFailure(result) }
        defer { posix_spawnattr_destroy(&attributes) }

        result = posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        )
        guard result == 0 else { throw GitHistoryRunnerFailure.processGroupFailed(errno: result) }
        result = posix_spawnattr_setpgroup(&attributes, 0)
        guard result == 0 else { throw GitHistoryRunnerFailure.processGroupFailed(errno: result) }

        let argumentStrings = [request.executableURL.path] + request.arguments
        var arguments: [UnsafeMutablePointer<CChar>?] = []
        arguments.reserveCapacity(argumentStrings.count + 1)
        for argument in argumentStrings {
            guard let pointer = strdup(argument) else {
                for pointer in arguments {
                    if let pointer { free(pointer) }
                }
                throw GitHistoryRunnerFailure.launchFailed("Unable to allocate process arguments")
            }
            arguments.append(pointer)
        }
        arguments.append(nil)
        defer {
            for pointer in arguments {
                if let pointer { free(pointer) }
            }
        }

        let environmentStrings = [
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL=en_US.UTF-8",
        ]
        var environment: [UnsafeMutablePointer<CChar>?] = []
        environment.reserveCapacity(environmentStrings.count + 1)
        for value in environmentStrings {
            guard let pointer = strdup(value) else {
                for pointer in environment {
                    if let pointer { free(pointer) }
                }
                throw GitHistoryRunnerFailure.launchFailed("Unable to allocate process environment")
            }
            environment.append(pointer)
        }
        environment.append(nil)
        defer {
            for pointer in environment {
                if let pointer { free(pointer) }
            }
        }

        var pid: pid_t = 0
        result = arguments.withUnsafeMutableBufferPointer { argumentBuffer in
            environment.withUnsafeMutableBufferPointer { environmentBuffer in
                posix_spawn(
                    &pid,
                    request.executableURL.path,
                    &actions,
                    &attributes,
                    argumentBuffer.baseAddress!,
                    environmentBuffer.baseAddress!
                )
            }
        }
        guard result == 0 else { throw launchFailure(result) }

        Darwin.close(stdoutPipe[1])
        stdoutPipe[1] = -1
        Darwin.close(stderrPipe[1])
        stderrPipe[1] = -1
        ownsDescriptors = false
        return SpawnedProcess(
            pid: pid,
            output: OutputDescriptorToken(stdout: stdoutPipe[0], stderr: stderrPipe[0])
        )
    }

    private static nonisolated func launchFailure(_ errorNumber: Int32) -> GitHistoryRunnerFailure {
        .launchFailed(String(cString: strerror(errorNumber)))
    }
}

private final class OutputDescriptorToken: @unchecked Sendable {
    let stdout: Int32
    let stderr: Int32
    private let lock = NSLock()
    private var closed = false

    init(stdout: Int32, stderr: Int32) {
        self.stdout = stdout
        self.stderr = stderr
    }

    var isClosed: Bool {
        lock.withLock { closed }
    }

    func closeAll() {
        let shouldClose = lock.withLock {
            guard !closed else { return false }
            closed = true
            return true
        }
        guard shouldClose else { return }
        Darwin.close(stdout)
        Darwin.close(stderr)
    }
}

/// Synchronizes process-group signals issued by cancellation and collection paths.
private final class ProcessGroupToken: @unchecked Sendable {
    private let lock = NSLock()
    private let pid: pid_t
    private var sentTermination = false

    init(pid: pid_t) {
        self.pid = pid
    }

    func terminate() {
        let shouldSignal = lock.withLock {
            guard !sentTermination else { return false }
            sentTermination = true
            return true
        }
        if shouldSignal { _ = Darwin.kill(-pid, SIGTERM) }
    }

    func killNow() {
        _ = Darwin.kill(-pid, SIGKILL)
    }
}

/// Atomically accounts for bytes read from both output descriptors.
private final class CombinedOutputBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var count = 0

    init(limit: Int) {
        self.limit = limit
    }

    func reserve(_ amount: Int) -> Bool {
        lock.withLock {
            guard amount <= limit - count else { return false }
            count += amount
            return true
        }
    }
}

/// Bridges synchronous task cancellation into the runner's structured event loop.
fileprivate final class CancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var signalled = false

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    var wasSignalled: Bool {
        lock.withLock { signalled }
    }

    func signal() {
        lock.withLock { signalled = true }
        continuation.yield(())
    }

    func finish() {
        continuation.finish()
    }

    func wait() async -> GitHistoryProcessRunner.Event {
        for await _ in stream {
            return .cancelled
        }
        return .cancelled
    }
}
