import SwiftUI

struct TitlebarPathView: View {
    var scanner: DirectoryScanner

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(scanner.currentDirectory.lastPathComponent.isEmpty ? "/" : scanner.currentDirectory.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Text(scanner.currentDirectory.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .help(scanner.currentDirectory.path)
    }
}

struct TitlebarGitBranchView: View {
    var status: GitRepositoryStatus
    @State private var isShowingBranches = false
    @State private var isShowingInitConfirmation = false

    var body: some View {
        Group {
            if status.isInGitRepository, let branchName = status.branchName {
                Button {
                    status.loadBranches()
                    isShowingBranches = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 12, weight: .semibold))

                        Text(branchName)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .padding(.trailing, 16)
                .frame(maxWidth: 640, alignment: .trailing)
                .help(status.repositoryRoot?.path ?? branchName)
                .popover(isPresented: $isShowingBranches, arrowEdge: .top) {
                    GitBranchPopoverView(status: status)
                        .frame(width: 320, height: 420)
                }
            } else {
                Button {
                    isShowingInitConfirmation = true
                } label: {
                    HStack(spacing: 5) {
                        if status.isInitializingRepository {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                        }

                        Text("Git Init")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(status.isInitializingRepository)
                .padding(.trailing, 16)
                .frame(maxWidth: 240, alignment: .trailing)
                .help(status.checkoutErrorMessage ?? String(format: String(localized: "%@에서 git init"), status.currentDirectory.path))
            }
        }
        .alert("Git 저장소를 초기화할까요?", isPresented: $isShowingInitConfirmation) {
            Button("취소", role: .cancel) {}
            Button("Git Init") {
                status.initializeRepository()
            }
        } message: {
            Text(String(format: String(localized: "%@에 .git 디렉토리를 생성합니다."), status.currentDirectory.path))
        }
    }
}

private struct GitBranchPopoverView: View {
    var status: GitRepositoryStatus

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear {
            status.loadBranches()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)

            Text("브랜치")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                status.loadBranches()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(status.isLoadingBranches || status.isCheckingOut)
            .help(String(localized: "브랜치 목록 새로고침"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if status.isLoadingBranches && status.localBranches.isEmpty && status.remoteBranchGroups.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    branchSection(
                        title: "LOCAL",
                        systemImage: "desktopcomputer",
                        count: status.localBranches.count
                    )

                    ForEach(status.localBranches) { branch in
                        branchRow(branch)
                    }

                    if !status.remoteBranchGroups.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                    }

                    branchSection(
                        title: "REMOTE",
                        systemImage: "icloud",
                        count: status.remoteBranchGroups.reduce(0) { $0 + $1.branches.count },
                        showsRemoteRefresh: true
                    )

                    ForEach(status.remoteBranchGroups) { group in
                        remoteHeader(group.remoteName)
                        ForEach(group.branches) { branch in
                            branchRow(branch, isRemoteChild: true)
                        }
                    }

                    if status.isCheckingOut {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("체크아웃 진행 중...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    } else if let message = status.checkoutErrorMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .disabled(status.isCheckingOut)
        }
    }

    private func branchSection(
        title: String,
        systemImage: String,
        count: Int,
        showsRemoteRefresh: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.blue)

            if showsRemoteRefresh {
                Button {
                    status.refreshBranchesFromRemotes()
                } label: {
                    if status.isLoadingBranches {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .disabled(status.isLoadingBranches || status.isCheckingOut)
                .help(String(localized: "원격 브랜치 새로고침"))
                .accessibilityIdentifier("git-refresh-remote-branches")
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func remoteHeader(_ remoteName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 11))
            Text(remoteName)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
    }

    private func branchRow(_ branch: GitBranch, isRemoteChild: Bool = false) -> some View {
        let isCurrent: Bool = {
            guard case .local = branch.kind else { return false }
            return branch.displayName == status.branchName
        }()

        return HStack(spacing: 8) {
            Image(systemName: isCurrent ? "checkmark.square.fill" : "arrow.triangle.branch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCurrent ? .green : .secondary)

            Text(branch.displayName)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
            
            if status.isCheckingOut && status.checkoutTargetBranch == branch {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.leading, isRemoteChild ? 46 : 28)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(isCurrent ? Color.green.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            status.checkout(branch)
        }
        .disabled(status.isCheckingOut)
        .help(String(format: String(localized: "클릭해서 %@ 체크아웃"), branch.checkoutName))
    }
}
