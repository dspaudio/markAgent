import SwiftUI

struct GitChangesSidebar: View {
    var state: GitDiffState
    var width: Double

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fileList
            if state.isLoadingSelectedDiff {
                Divider()
                ProgressView("Diff 불러오는 중...")
                    .font(.system(size: 12))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let diffResult = state.selectedDiffResult {
                Divider()
                DiffOverlayView(diffResult: diffResult, baseURL: state.selectedFile?.url.deletingLastPathComponent()) {
                    state.clearSelection()
                }
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(appColors?.panel ?? Color(NSColor.controlBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .foregroundStyle(.secondary)
            Text("Git 변경 파일")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            if state.isRefreshing {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 14, height: 14)
            }
            Button {
                if let root = state.repositoryRoot {
                    state.refresh(for: root)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("새로고침")
            .disabled(state.isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var fileList: some View {
        if let errorMessage = state.errorMessage {
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
                            state.select(file)
                        } label: {
                            GitChangedFileRow(
                                file: file,
                                isSelected: state.selectedFile == file
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: state.selectedDiffResult == nil ? .infinity : 220)
            .opacity(state.isRefreshing ? 0.72 : 1)
        }
    }
}

private struct GitChangedFileRow: View {
    let file: GitChangedFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(file.status.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

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
}
