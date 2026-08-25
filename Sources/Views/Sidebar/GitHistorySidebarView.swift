import SwiftUI

struct GitHistorySidebarView: View {
    var store: GitHistoryStore
    var repositoryRoot: URL?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: repositoryRoot?.standardizedFileURL.path) {
                await store.refresh(repositoryRoot: repositoryRoot)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView("Git 히스토리 불러오는 중...")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noRepository:
            statusMessage("현재 작업 경로는 Git 저장소가 아닙니다.")
        case .failed:
            errorState
        case .loaded where store.commits.isEmpty:
            statusMessage("표시할 커밋이 없습니다.")
        case .loaded:
            loadedContent
        }
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Git 히스토리를 불러오지 못했습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.red)

            Button("다시 시도") {
                Task {
                    await store.refresh(repositoryRoot: repositoryRoot)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var loadedContent: some View {
        VSplitView {
            commitList
            commitDetails
        }
    }

    private var commitList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.commits) { commit in
                    GitHistoryCommitRow(
                        commit: commit,
                        isSelected: store.selectedCommitID == commit.id,
                        onSelect: {
                            store.selectCommit(id: commit.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var commitDetails: some View {
        if let commit = store.selectedCommit {
            ScrollView {
                GitHistoryCommitDetails(commit: commit)
                    .padding(12)
            }
        } else {
            statusMessage("커밋을 선택하세요.")
        }
    }
}

private struct GitHistoryCommitRow: View {
    let commit: GitCommit
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text(commit.authorName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(commit.authoredAt, format: .dateTime.year().month().day().hour().minute())
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("git-history-commit-\(commit.id)")
    }
}

private struct GitHistoryCommitDetails: View {
    let commit: GitCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(commit.subject)
                .font(.system(size: 13, weight: .bold))
                .textSelection(.enabled)

            detailField("커밋", value: commit.id, monospaced: true)
            detailField("작성자", value: "\(commit.authorName) <\(commit.authorEmail)>")
            detailField(
                "날짜",
                value: commit.authoredAt.formatted(date: .long, time: .standard)
            )

            if !commit.body.isEmpty {
                Divider()
                Text(commit.body)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailField(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
