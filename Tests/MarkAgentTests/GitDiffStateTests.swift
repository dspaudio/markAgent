import XCTest
@testable import ma

final class GitDiffStateTests: XCTestCase {
    @MainActor
    func testRefreshPreservesSelectedFileDiff() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }

        let fileURL = repository.appendingPathComponent("notes.md")
        try "base\nchanged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let state = GitDiffState()
        state.refresh(for: repository)
        try await waitUntil { !state.changedFiles.isEmpty && !state.isRefreshing }

        let file = try XCTUnwrap(state.changedFiles.first)
        state.select(file)
        try await waitUntil { state.selectedDiffResult != nil && !state.isLoadingSelectedDiff }

        state.refresh(for: repository)
        try await waitUntil { !state.isRefreshing && state.selectedDiffResult != nil }

        XCTAssertEqual(state.selectedFile?.relativePath, "notes.md")
        XCTAssertEqual(state.selectedDiffResult?.addedCount, 1)
    }

    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitDiffStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fileURL = root.appendingPathComponent("notes.md")
        _ = try runGit(["init"], in: root)
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "notes.md"], in: root)
        _ = try runGit(["commit", "-m", "initial"], in: root)

        return root
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
            throw NSError(domain: "GitDiffStateTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: error.isEmpty ? output : error,
            ])
        }

        return output
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout {
                throw NSError(domain: "GitDiffStateTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Timed out waiting for GitDiffState update.",
                ])
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
