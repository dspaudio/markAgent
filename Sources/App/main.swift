import AppKit

let cliArgs = CLIArguments.parse(CommandLine.arguments)

if cliArgs.showHelp {
    print(CLIArguments.usageText)
    exit(0)
}

// .app 번들 내부에서 실행 중이 아니면 번들을 찾아 재실행
let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    .resolvingSymlinksInPath()

if !executableURL.path.contains(".app/Contents/MacOS/") {
    // 바이너리 위치 기준 상위 3단계까지 MarkAgent.app 탐색
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
    // .app 번들을 찾지 못하면 직접 실행 (Dock/메뉴 미지원)
    fputs("warning: MarkAgent.app 번들을 찾지 못했습니다. scripts/bundle.sh를 먼저 실행하세요.\n", stderr)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate(cliArguments: cliArgs)
app.delegate = delegate
app.run()
