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

    @MainActor
    private func waitForGitStatusUpdate() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }
}
