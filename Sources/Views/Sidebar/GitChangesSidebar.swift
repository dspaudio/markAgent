import SwiftUI

struct GitChangesSidebar: View {
    var state: GitDiffState
    var onSelectFile: (GitChangedFile) -> Void

    var body: some View {
        fileList
            .frame(maxHeight: .infinity)
        .onAppear {
            state.loadAllDiffs()
        }
        .onChange(of: state.changedFiles.map(\.id)) { _, _ in
            state.loadAllDiffs()
        }
    }

    private var fileList: some View {
        Group {
            if !state.isInGitRepository {
                Text("현재 작업 경로는 Git 저장소가 아닙니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if state.changedFiles.isEmpty {
                Text("마지막 커밋 이후 변경된 파일이 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.changedFiles) { file in
                            Button {
                                onSelectFile(file)
                            } label: {
                                GitChangedFileRow(
                                    file: file,
                                    diffResult: state.fileDiffs.first { $0.file.id == file.id }?.diffResult,
                                    isLoadingDiff: state.isLoadingDiffs,
                                    isSelected: state.selectedFile == file
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .opacity(state.isRefreshing ? 0.72 : 1)
            }
        }
    }
}

private struct GitChangedFileRow: View {
    let file: GitChangedFile
    let diffResult: DiffResult?
    let isLoadingDiff: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(file.status.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    diffSummary
                }

                Text(file.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }

    @ViewBuilder
    private var diffSummary: some View {
        if let diffResult {
            HStack(spacing: 4) {
                Text("+\(diffResult.addedCount)")
                    .foregroundStyle(.green)
                Text("-\(diffResult.removedCount)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .layoutPriority(1)
        } else if isLoadingDiff {
            Text("+… -…")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
