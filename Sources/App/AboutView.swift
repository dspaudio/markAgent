import AppKit
import SwiftUI

struct AboutView: View {
    static let githubURLString = "https://github.com/dspaudio/markAgent"

    private let libraries: [OpenSourceLibrary] = [
        OpenSourceLibrary(
            name: "swift-markdown",
            role: "GitHub Flavored Markdown parsing",
            license: "Apache-2.0",
            url: "https://github.com/swiftlang/swift-markdown"
        ),
        OpenSourceLibrary(
            name: "swift-cmark",
            role: "CommonMark and GFM parsing engine used by swift-markdown",
            license: "BSD-style and MIT notices",
            url: "https://github.com/swiftlang/swift-cmark"
        ),
        OpenSourceLibrary(
            name: "HighlightSwift",
            role: "Code block syntax highlighting",
            license: "MIT; includes highlight.js under BSD-3-Clause",
            url: "https://github.com/appstefan/HighlightSwift"
        ),
        OpenSourceLibrary(
            name: "libghostty-spm",
            role: "Embedded terminal surface and Ghostty integration",
            license: "MIT; bundles libghostty under its own MIT terms",
            url: "https://github.com/Lakr233/libghostty-spm"
        ),
        OpenSourceLibrary(
            name: "MSDisplayLink",
            role: "Display refresh support used by libghostty-spm",
            license: "MIT",
            url: "https://github.com/Lakr233/MSDisplayLink"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .padding(.bottom, 22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(title: "GitHub") {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Self.githubURLString)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 16)

                            Button("Open Repository") {
                                open(Self.githubURLString)
                            }
                        }
                    }

                    section(title: "Open Source Libraries") {
                        VStack(spacing: 10) {
                            ForEach(libraries) { library in
                                LibraryRow(library: library)
                            }
                        }
                    }

                    section(title: "License Notice") {
                        Text("MarkAgent includes and links against the open source components listed above. Each component remains governed by its respective license.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

            VStack(spacing: 6) {
                Text("MarkAgent")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("The Professional GUI for your CLI AI Agents.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Text("CLI AI 에이전트가 만든 마크다운을 macOS에서 바로 읽고 편집하는 네이티브 브릿지입니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appIcon: NSImage {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }

        return NSApplication.shared.applicationIconImage
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?) where version != build:
            return "Version \(version) (\(build))"
        case let (version?, _):
            return "Version \(version)"
        default:
            return "Version 1.0.0"
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct LibraryRow: View {
    let library: OpenSourceLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(library.name)
                    .font(.body.weight(.semibold))

                Spacer(minLength: 12)

                Text(library.license)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            Text(library.role)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(library.url)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OpenSourceLibrary: Identifiable {
    let name: String
    let role: String
    let license: String
    let url: String

    var id: String { name }
}
