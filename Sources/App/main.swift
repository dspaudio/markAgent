import AppKit

let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    .resolvingSymlinksInPath()

if CommandLine.arguments.dropFirst().first == "--claude-statusline" {
    do {
        var input = Data()
        let limit = 1_048_576
        while let chunk = try FileHandle.standardInput.read(upToCount: min(65_536, limit + 1 - input.count)),
              !chunk.isEmpty {
            input.append(chunk)
            guard input.count <= limit else { throw ClaudeStatuslineUsageError.malformedData }
        }
        if try ClaudeStatuslineUsageStore.save(input) {
            DistributedNotificationCenter.default().postNotificationName(
                ClaudeStatuslineUsageStore.notificationName,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        exit(0)
    } catch {
        fputs("MarkAgent: Claude status line usage could not be saved.\n", stderr)
        exit(1)
    }
}

if let argument = CommandLine.arguments.dropFirst().first,
   argument == "--install-claude-statusline" || argument == "--uninstall-claude-statusline" {
    do {
        if argument == "--install-claude-statusline" {
            try ClaudeStatuslineIntegration.install(executableURL: executableURL)
        } else {
            try ClaudeStatuslineIntegration.uninstall()
        }
        exit(0)
    } catch {
        fputs("MarkAgent: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if !executableURL.path.contains(".app/Contents/MacOS/") {
    var searchDir = executableURL.deletingLastPathComponent()
    for _ in 0..<3 {
        let candidate = searchDir.appendingPathComponent("MarkAgent.app")
        if FileManager.default.fileExists(atPath: candidate.path) {
            let forwardedArguments = CommandLine.arguments.dropFirst().map { argument in
                guard !argument.hasPrefix("-") else { return argument }

                if argument.hasPrefix("/") || argument.hasPrefix("~") {
                    return NSString(string: argument).expandingTildeInPath
                }

                let cwd = FileManager.default.currentDirectoryPath
                return URL(fileURLWithPath: cwd).appendingPathComponent(argument).path
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [candidate.path, "--args"] + forwardedArguments
            try? process.run()
            process.waitUntilExit()
            exit(process.terminationStatus)
        }
        searchDir = searchDir.deletingLastPathComponent()
    }
    fputs(String(localized: "warning: MarkAgent.app 번들을 찾지 못했습니다. scripts/bundle.sh를 먼저 실행하세요.\n"), stderr)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
