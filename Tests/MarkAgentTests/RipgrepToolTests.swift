import XCTest
@testable import ma

final class RipgrepToolTests: XCTestCase {
    func testExecutableURLFindsFirstExecutablePath() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appending(path: "first-rg")
        let second = root.appending(path: "second-rg")
        try writeExecutable(to: second)

        let result = RipgrepTool.executableURL(paths: [first.path, second.path])

        XCTAssertEqual(result?.path, second.path)
    }

    func testExecutableURLIgnoresNonExecutablePath() throws {
        let root = try makeTemporaryDirectory()
        let candidate = root.appending(path: "rg")
        try "not executable".write(to: candidate, atomically: true, encoding: .utf8)

        let result = RipgrepTool.executableURL(paths: [candidate.path])

        XCTAssertNil(result)
    }

    func testHomebrewURLFindsExecutableBrewPath() throws {
        let root = try makeTemporaryDirectory()
        let brew = root.appending(path: "brew")
        try writeExecutable(to: brew)

        let result = RipgrepTool.homebrewURL(paths: [brew.path])

        XCTAssertEqual(result?.path, brew.path)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "markagent-ripgrep-tool-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func writeExecutable(to url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
