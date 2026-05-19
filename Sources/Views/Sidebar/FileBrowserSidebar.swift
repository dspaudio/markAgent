import SwiftUI

struct FileBrowserSidebar: View {
    var scanner: DirectoryScanner
    var recentStore: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenMarkdown: (URL) -> Void
    var onOpenOtherFile: (URL) -> Void
    
    @State private var selectedEntryID: String?
    
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
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func handleDoubleClick(_ entry: FileEntry) {
        switch entry.kind {
        case .directory:
            scanner.enterDirectory(entry.url)
        case .markdown:
            onOpenMarkdown(entry.url)
        case .file:
            onOpenOtherFile(entry.url)
        }
    }
}
