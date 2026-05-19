import AppKit

let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    .resolvingSymlinksInPath()

if !executableURL.path.contains(".app/Contents/MacOS/") {
    var searchDir = executableURL.deletingLastPathComponent()
    for _ in 0..<3 {
        let candidate = searchDir.appendingPathComponent("MarkAgent.app")
        if FileManager.default.fileExists(atPath: candidate.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [candidate.path, "--args"] + Array(CommandLine.arguments.dropFirst())
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
