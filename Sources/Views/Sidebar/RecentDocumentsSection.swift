import SwiftUI

struct RecentDocumentsSection: View {
    var store: RecentDocumentStore
    var currentFileURL: URL?
    var onOpen: (URL) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("최근 문서")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !store.documents.isEmpty {
                    Text("\(store.documents.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            if store.documents.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 2) {
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
                .padding(.bottom, 8)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("최근 문서 없음")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
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
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(document.directory)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(String(localized: "최근 문서에서 제거"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
