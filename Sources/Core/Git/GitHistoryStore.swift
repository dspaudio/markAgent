import Foundation

struct GitCommit: Identifiable, Equatable, Sendable {
    let id: String
    let shortHash: String
    let authorName: String
    let authorEmail: String
    let authoredAt: Date
    let subject: String
    let body: String
}

enum GitHistoryFailure: Error, Equatable, Sendable {
    case runner(GitHistoryRunnerFailure)
    case invalidUTF8
    case malformedRecord
    case invalidHash(String)
    case invalidDate(String)
}

enum GitHistoryLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case noRepository
    case failed(GitHistoryFailure)
}

enum GitHistoryCommand {
    static let timeoutSeconds = 5
    static let outputByteLimit = 4_194_304

    static func request(repositoryRoot: URL) -> GitHistoryProcessRequest {
        GitHistoryProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "-C", repositoryRoot.path,
                "log", "--all", "--max-count=100", "--date=iso-strict",
                "--pretty=format:%H%x00%h%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00",
            ],
            timeoutSeconds: timeoutSeconds,
            outputByteLimit: outputByteLimit
        )
    }
}

@MainActor
@Observable
final class GitHistoryStore {
    typealias Parser = @Sendable (Data) throws -> [GitCommit]

    private(set) var state: GitHistoryLoadState = .idle
    private(set) var commits: [GitCommit] = []
    private(set) var selectedCommitID: GitCommit.ID?

    private let commandRunner: GitHistoryCommandRunner
    private let parser: Parser
    private var refreshGeneration = 0
    private var repositoryRoot: URL?

    init(
        commandRunner: @escaping GitHistoryCommandRunner = GitHistoryProcessRunner.run,
        parser: @escaping Parser = GitHistoryStore.parse
    ) {
        self.commandRunner = commandRunner
        self.parser = parser
    }

    var selectedCommit: GitCommit? {
        guard let selectedCommitID else { return nil }
        return commits.first { $0.id == selectedCommitID }
    }

    func selectCommit(id: GitCommit.ID) {
        selectedCommitID = commits.contains { $0.id == id } ? id : nil
    }

    func refresh(repositoryRoot: URL?) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let requestedRoot = repositoryRoot?.standardizedFileURL
        self.repositoryRoot = requestedRoot

        guard let requestedRoot else {
            state = .noRepository
            commits = []
            selectedCommitID = nil
            return
        }

        state = .loading
        do {
            let output = try await commandRunner(GitHistoryCommand.request(repositoryRoot: requestedRoot))
            guard canPublish(generation: generation, repositoryRoot: requestedRoot) else { return }

            let parser = parser
            let stdout = output.stdout
            let parsedCommits = try await Task.detached(priority: .utility) {
                try parser(stdout)
            }.value
            guard canPublish(generation: generation, repositoryRoot: requestedRoot) else { return }

            let previousSelection = selectedCommitID
            commits = parsedCommits
            if let previousSelection, parsedCommits.contains(where: { $0.id == previousSelection }) {
                selectedCommitID = previousSelection
            } else {
                selectedCommitID = parsedCommits.first?.id
            }
            state = .loaded
        } catch let failure as GitHistoryFailure {
            publish(failure, generation: generation, repositoryRoot: requestedRoot)
        } catch let failure as GitHistoryRunnerFailure {
            publish(.runner(failure), generation: generation, repositoryRoot: requestedRoot)
        } catch is CancellationError {
            publish(.runner(.cancelled), generation: generation, repositoryRoot: requestedRoot)
        } catch {
            publish(
                .runner(.launchFailed(String(describing: error))),
                generation: generation,
                repositoryRoot: requestedRoot
            )
        }
    }

    private func publish(_ failure: GitHistoryFailure, generation: Int, repositoryRoot: URL) {
        guard canPublish(generation: generation, repositoryRoot: repositoryRoot) else { return }
        commits = []
        selectedCommitID = nil
        state = .failed(failure)
    }

    private func canPublish(generation: Int, repositoryRoot: URL) -> Bool {
        !Task.isCancelled
            && generation == refreshGeneration
            && repositoryRoot == self.repositoryRoot
    }

    private nonisolated static func parse(_ data: Data) throws -> [GitCommit] {
        guard !data.isEmpty else { return [] }
        guard let output = String(data: data, encoding: .utf8) else {
            throw GitHistoryFailure.invalidUTF8
        }

        var fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        guard fields.last == "" else { throw GitHistoryFailure.malformedRecord }
        fields.removeLast()
        guard fields.count.isMultiple(of: 7) else { throw GitHistoryFailure.malformedRecord }

        var commits: [GitCommit] = []
        commits.reserveCapacity(fields.count / 7)
        for recordIndex in 0..<(fields.count / 7) {
            let offset = recordIndex * 7
            var hash = fields[offset]
            if recordIndex > 0, hash.first == "\n" {
                hash.removeFirst()
            }
            guard (hash.count == 40 || hash.count == 64),
                  hash.utf8.allSatisfy(Self.isHexDigit) else {
                throw GitHistoryFailure.invalidHash(hash)
            }
            let shortHash = fields[offset + 1]
            guard !shortHash.isEmpty, shortHash.utf8.allSatisfy(Self.isHexDigit) else {
                throw GitHistoryFailure.invalidHash(shortHash)
            }

            let dateText = fields[offset + 4]
            guard let authoredAt = parseISO8601(dateText) else {
                throw GitHistoryFailure.invalidDate(dateText)
            }
            commits.append(GitCommit(
                id: hash,
                shortHash: shortHash,
                authorName: fields[offset + 2],
                authorEmail: fields[offset + 3],
                authoredAt: authoredAt,
                subject: fields[offset + 5],
                body: fields[offset + 6]
            ))
        }
        return commits
    }

    private nonisolated static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private nonisolated static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
