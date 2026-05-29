import SwiftUI

struct RecentDocumentsSidebar: View {
    var store: RecentDocumentStore
    var currentFileURL: URL?
    var onOpenFile: () -> Void
    var onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("최근 문서")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(store.documents.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Button(action: onOpenFile) {
                Label("파일 열기", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            if store.documents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.documents) { document in
                            RecentDocumentRow(
                                document: document,
                                isSelected: document.path == currentFileURL?.path,
                                onOpen: {
                                    onOpen(URL(fileURLWithPath: document.path))
                                },
                                onRemove: {
                                    store.remove(document)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("최근 문서 없음")
                .font(.subheadline.weight(.semibold))

            Text("파일을 열면 여기에 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentDocumentRow: View {
    let document: RecentDocument
    let isSelected: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text(document.directory)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(String(localized: "최근 문서에서 제거"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
