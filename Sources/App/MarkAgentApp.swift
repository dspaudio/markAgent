import SwiftUI

@main
struct MarkAgentApp: App {
    @State private var document = MarkdownDocument()

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
                .onAppear {
                    loadFromCLIArguments()
                }
        }
    }

    private func loadFromCLIArguments() {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            document.errorMessage = DocumentError.noFileSpecified.errorDescription
            return
        }

        let path = args[1]
        switch MarkdownDocument.resolveFileURL(from: path) {
        case .success(let url):
            document.load(from: url)
        case .failure(let error):
            document.errorMessage = error.errorDescription
        }
    }
}
