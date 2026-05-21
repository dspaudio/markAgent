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

    var body: some View {
        if status.isInGitRepository, let branchName = status.branchName {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))

                Text(branchName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: 260, alignment: .trailing)
            .help(status.repositoryRoot?.path ?? branchName)
        }
    }
}
