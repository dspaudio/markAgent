import AppKit

let cliArgs = CLIArguments.parse(CommandLine.arguments)

if cliArgs.showHelp {
    print(CLIArguments.usageText)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(cliArguments: cliArgs)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
