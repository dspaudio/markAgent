import AppKit

let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    .resolvingSymlinksInPath()

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
    fputs("warning: MarkAgent.app 번들을 찾지 못했습니다. scripts/bundle.sh를 먼저 실행하세요.\n", stderr)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
