import SwiftUI

struct ContentView: View {
    var document: MarkdownDocument

    var body: some View {
        Group {
            if let errorMessage = document.errorMessage {
                errorView(message: errorMessage)
            } else if document.content.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private var contentView: some View {
        ScrollView {
            renderMarkdown(document.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("파일을 로드하는 중...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
