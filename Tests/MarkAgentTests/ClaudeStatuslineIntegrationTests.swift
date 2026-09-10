import XCTest
@testable import ma

final class ClaudeStatuslineIntegrationTests: XCTestCase {
    func testInstallPreservesSettingsAndBacksUpOnlyOriginalStatusline() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("""
        {"model":"opus","env":{"EXAMPLE":"secret-must-not-be-backed-up"},"statusLine":{"type":"command","command":"printf original","padding":3,"custom":true}}

        """.utf8)
        try fixture.writeSettings(original)

        try fixture.install()

        let settings = try fixture.settings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertEqual((settings["env"] as? [String: String])?["EXAMPLE"], "secret-must-not-be-backed-up")
        let statusline = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(statusline["type"] as? String, "command")
        XCTAssertEqual(statusline["padding"] as? Int, 3)
        XCTAssertEqual(statusline["custom"] as? Bool, true)
        XCTAssertTrue(fixture.isInstalled)

        let backup = try fixture.artifact(named: "settings-backup.json")
        let backupObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any])
        let encodedOriginal = try XCTUnwrap(backupObject["originalStatusline"] as? String)
        let backupStatusline = try XCTUnwrap(Data(base64Encoded: encodedOriginal))
        let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: backupStatusline) as? [String: Any])
        XCTAssertEqual(originalObject["command"] as? String, "printf original")
        XCTAssertEqual(originalObject["padding"] as? Int, 3)
        XCTAssertNil(backupObject["originalSettings"])
        XCTAssertEqual(Set(backupObject.keys), ["settingsPath", "settingsExisted", "originalStatusline"])
        XCTAssertFalse(String(decoding: backupStatusline, as: UTF8.self).contains("secret-must-not-be-backed-up"))
        let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try fixture.uninstall()

        XCTAssertFalse(fixture.isInstalled)
        XCTAssertTrue(NSDictionary(dictionary: try fixture.settings()).isEqual(to: try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])))
    }

    func testInstallWithoutSettingsAndUninstallRemovesCreatedSettings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        try fixture.install()

        XCTAssertTrue(fixture.isInstalled)
        XCTAssertEqual(try fixture.settings().count, 1)
        let result = try fixture.runStatusline(input: Data("{}\n".utf8))
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.isEmpty)

        try fixture.uninstall()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.settingsURL.path))
        XCTAssertFalse(fixture.isInstalled)
    }

    func testReinstallUpdatesExecutableAndPreservesOriginalBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"/bin/cat\"}}".utf8)
        try fixture.writeSettings(original)
        try fixture.install()
        let firstSettings = try Data(contentsOf: fixture.settingsURL)
        let firstBackup = try Data(contentsOf: fixture.artifact(named: "settings-backup.json"))

        try fixture.install()
        XCTAssertEqual(try Data(contentsOf: fixture.settingsURL), firstSettings)
        XCTAssertEqual(try Data(contentsOf: fixture.artifact(named: "settings-backup.json")), firstBackup)

        let upgradedExecutable = fixture.home.appendingPathComponent("New 'App' $bin;!/ma")
        try fixture.writeExecutable(at: upgradedExecutable, contents: "#!/bin/sh\n/bin/cat > \"$CAPTURE\"\nprintf upgraded > \"$VERSION_FILE\"\n")
        try ClaudeStatuslineIntegration.install(
            executableURL: upgradedExecutable,
            homeDirectory: fixture.home,
            environment: fixture.environment
        )
        let input = Data("{\"version\":2}\n\n".utf8)
        let result = try fixture.runStatusline(input: input)

        XCTAssertEqual(result.output, input)
        XCTAssertEqual(try String(contentsOf: fixture.versionFile, encoding: .utf8), "upgraded")
        XCTAssertEqual(try Data(contentsOf: fixture.artifact(named: "settings-backup.json")), firstBackup)

        try fixture.uninstall()
        XCTAssertTrue(NSDictionary(dictionary: try fixture.settings()).isEqual(to: try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])))
    }

    func testWrapperPreservesOriginalStdinStdoutAndExitStatusWithShellMetacharacters() throws {
        let fixture = try Fixture(homeName: "Home 'quoted' $variable;`literal`")
        defer { fixture.remove() }
        try fixture.writeSettings([
            "statusLine": [
                "type": "command",
                "command": "printf '%s' 'prefix:$literal;'; /bin/cat; printf '%s' ':suffix'; exit 23",
                "padding": 2,
            ],
        ])
        try fixture.install()
        let input = Data("{\"rate_limits\":{},\"literal\":\"$() `x` ' \\\"\"}\n\n".utf8)

        let result = try fixture.runStatusline(input: input)

        XCTAssertEqual(result.status, 23)
        XCTAssertEqual(result.output, Data("prefix:$literal;".utf8) + input + Data(":suffix".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.captureFile), input)
    }

    func testCustomConfigDirectoryDoesNotWriteDefaultClaudeDirectory() throws {
        let fixture = try Fixture(customConfig: "custom 'claude' $config")
        defer { fixture.remove() }
        try fixture.writeSettings(["model": "sonnet"])

        try fixture.install()

        XCTAssertTrue(fixture.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent(".claude").path))
        XCTAssertEqual(try fixture.settings()["model"] as? String, "sonnet")
        try fixture.uninstall()
        XCTAssertEqual(try fixture.settings()["model"] as? String, "sonnet")
    }

    func testTildeConfigDirectoryUsesProvidedHomeDirectory() throws {
        let fixture = try Fixture(customConfig: "custom-config")
        defer { fixture.remove() }
        try fixture.writeSettings(["model": "opus"])

        try ClaudeStatuslineIntegration.install(
            executableURL: fixture.executable,
            homeDirectory: fixture.home,
            environment: ["CLAUDE_CONFIG_DIR": "~/custom-config"]
        )

        XCTAssertTrue(fixture.isInstalled)
        XCTAssertEqual(try fixture.settings()["model"] as? String, "opus")
        try fixture.uninstall()
    }

    func testInvalidJSONAndUnsupportedStatuslineLeaveSettingsUntouched() throws {
        let fixtures = [
            "{broken json",
            "[]",
            "{\"statusLine\":null}",
            "{\"statusLine\":\"/bin/cat\"}",
            "{\"statusLine\":{\"type\":\"plugin\",\"command\":\"/bin/cat\"}}",
            "{\"statusLine\":{\"type\":\"command\"}}",
        ]
        for contents in fixtures {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let original = Data(contents.utf8)
            try fixture.writeSettings(original)

            XCTAssertThrowsError(try fixture.install())

            XCTAssertEqual(try Data(contentsOf: fixture.settingsURL), original)
            XCTAssertFalse(fixture.isInstalled)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.integrationDirectory.path))
        }
    }

    func testUninstallPreservesUserReplacementAndOtherSettingsEdits() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSettings(["model": "opus", "statusLine": ["type": "command", "command": "/bin/cat"]])
        try fixture.install()
        let replacement = Data("{\"model\":\"sonnet\",\"statusLine\":{\"type\":\"command\",\"command\":\"printf replacement\"}}".utf8)
        try fixture.writeSettings(replacement)

        try fixture.uninstall()

        XCTAssertEqual(try Data(contentsOf: fixture.settingsURL), replacement)
        XCTAssertFalse(fixture.isInstalled)
    }

    func testReconnectAfterUserReplacementRestoresTheLatestUserCommand() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSettings(["statusLine": ["type": "command", "command": "printf old"]])
        try fixture.install()
        try fixture.writeSettings(["statusLine": ["type": "command", "command": "printf new", "padding": 5]])

        try fixture.install()
        try fixture.uninstall()

        let statusline = try XCTUnwrap(fixture.settings()["statusLine"] as? [String: Any])
        XCTAssertEqual(statusline["command"] as? String, "printf new")
        XCTAssertEqual(statusline["padding"] as? Int, 5)
    }

    func testUninstallRestoresCommandAndPreservesLaterPaddingAndModelChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSettings([
            "model": "opus",
            "statusLine": ["type": "command", "command": "printf original", "padding": 1],
        ])
        try fixture.install()
        var edited = try fixture.settings()
        var statusline = try XCTUnwrap(edited["statusLine"] as? [String: Any])
        statusline["padding"] = 8
        edited["statusLine"] = statusline
        edited["model"] = "sonnet"
        try fixture.writeSettings(edited)

        try fixture.uninstall()

        let restored = try fixture.settings()
        let restoredStatusline = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(restored["model"] as? String, "sonnet")
        XCTAssertEqual(restoredStatusline["command"] as? String, "printf original")
        XCTAssertEqual(restoredStatusline["padding"] as? Int, 8)
    }

    func testUninstallWithoutOriginalSettingsPreservesLaterUnrelatedSettings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.install()
        var edited = try fixture.settings()
        edited["model"] = "sonnet"
        try fixture.writeSettings(edited)

        try fixture.uninstall()

        let restored = try fixture.settings()
        XCTAssertEqual(restored["model"] as? String, "sonnet")
        XCTAssertNil(restored["statusLine"])
    }

    func testMissingBackupPreventsUninstallFromDestroyingSettings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSettings(["statusLine": ["type": "command", "command": "printf original"]])
        try fixture.install()
        let installed = try Data(contentsOf: fixture.settingsURL)
        try FileManager.default.removeItem(at: fixture.artifact(named: "settings-backup.json"))

        XCTAssertThrowsError(try fixture.uninstall())
        XCTAssertThrowsError(try fixture.install())

        XCTAssertEqual(try Data(contentsOf: fixture.settingsURL), installed)
    }

    func testInstallationArtifactWriteFailureLeavesSettingsUntouched() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"printf original\"}}".utf8)
        try fixture.writeSettings(original)
        try FileManager.default.createDirectory(at: fixture.integrationDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cannot be a directory".utf8).write(to: fixture.integrationDirectory)

        XCTAssertThrowsError(try fixture.install())

        XCTAssertEqual(try Data(contentsOf: fixture.settingsURL), original)
    }

    private struct Fixture {
        let root: URL
        let home: URL
        let settingsURL: URL
        let executable: URL
        let environment: [String: String]

        var integrationDirectory: URL {
            home.appendingPathComponent("Library/Application Support/MarkAgent/ClaudeStatusline")
        }
        var captureFile: URL { root.appendingPathComponent("captured.json") }
        var versionFile: URL { root.appendingPathComponent("version") }
        var isInstalled: Bool {
            ClaudeStatuslineIntegration.isInstalled(homeDirectory: home, environment: environment)
        }

        init(homeName: String = "home", customConfig: String? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeStatuslineIntegrationTests-\(UUID().uuidString)")
            home = root.appendingPathComponent(homeName)
            if let customConfig {
                let directory = home.appendingPathComponent(customConfig)
                environment = ["CLAUDE_CONFIG_DIR": directory.path]
                settingsURL = directory.appendingPathComponent("settings.json")
            } else {
                environment = [:]
                settingsURL = home.appendingPathComponent(".claude/settings.json")
            }
            executable = home.appendingPathComponent("Fake 'MarkAgent' $bin;`literal`/ma")
            try writeExecutable(at: executable, contents: """
            #!/bin/sh
            [ "$1" = "--claude-statusline" ] || exit 91
            /bin/cat > "$CAPTURE"
            printf '%s' helper-output
            exit 7

            """)
        }

        func install() throws {
            try ClaudeStatuslineIntegration.install(executableURL: executable, homeDirectory: home, environment: environment)
        }

        func uninstall() throws {
            try ClaudeStatuslineIntegration.uninstall(homeDirectory: home, environment: environment)
        }

        func writeSettings(_ data: Data) throws {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: settingsURL)
        }

        func writeSettings(_ settings: [String: Any]) throws {
            try writeSettings(JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]))
        }

        func settings() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        }

        func writeExecutable(at url: URL, contents: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }

        func artifact(named name: String) throws -> URL {
            let directory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: integrationDirectory, includingPropertiesForKeys: nil).first)
            return directory.appendingPathComponent(name)
        }

        func runStatusline(input: Data) throws -> (output: Data, status: Int32) {
            let statusline = try XCTUnwrap(settings()["statusLine"] as? [String: Any])
            let command = try XCTUnwrap(statusline["command"] as? String)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = ["CAPTURE": captureFile.path, "VERSION_FILE": versionFile.path]
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            try inputPipe.fileHandleForWriting.write(contentsOf: input)
            try inputPipe.fileHandleForWriting.close()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (output, process.terminationStatus)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
