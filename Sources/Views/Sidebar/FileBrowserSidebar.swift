import SwiftUI

struct FileBrowserSidebar: View {
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenMarkdown: (URL) -> Void
    var onOpenOtherFile: (URL) -> Void
    
    @State private var selectedEntryID: String?
    @State private var previewImage: SidebarImageSelection?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scanner.currentDirectory.lastPathComponent)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button(action: {
                    scanner.goUp()
                }) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(scanner.currentDirectory.path == "/")
                .help("상위 폴더로 이동")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if scanner.isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .padding()
                    } else if let error = scanner.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding()
                    } else if scanner.entries.isEmpty {
                        Text("빈 폴더")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(scanner.entries) { entry in
                            FileEntryRow(
                                entry: entry,
                                isSelected: selectedEntryID == entry.id || currentFileURL?.path == entry.url.path
                            )
                            .onTapGesture(count: 2) {
                                handleDoubleClick(entry)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                selectedEntryID = entry.id
                            })
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            ScrollView {
                RecentDocumentsSection(
                    store: recentStore,
                    currentFileURL: currentFileURL,
                    onOpen: { url in
                        onOpenMarkdown(url)
                    }
                )
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(appColors?.panel ?? Color(NSColor.controlBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .sheet(item: $previewImage) { selection in
            SidebarImageViewer(url: selection.url)
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
    
    private func handleDoubleClick(_ entry: FileEntry) {
        switch entry.kind {
        case .directory:
            scanner.enterDirectory(entry.url)
        case .markdown:
            onOpenMarkdown(entry.url)
        case .image:
            previewImage = SidebarImageSelection(url: entry.url)
        case .file:
            onOpenOtherFile(entry.url)
        }
    }
}

private struct SidebarImageSelection: Identifiable {
    let url: URL

    var id: String { url.path }
}

private struct SidebarImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            image = NSImage(contentsOf: url)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("닫기", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 1400, maxHeight: 1000)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.red)
                Text("이미지를 열 수 없습니다.")
                    .font(.headline)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
