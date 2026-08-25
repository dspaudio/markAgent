import AppKit
import SwiftUI

@MainActor
struct ProjectSidebar: View {
    var projectStore: ProjectStore
    var controller: ProjectSidebarController
    var activeWorkspaceID: TabWorkspaceID
    var width: Double
    var onHide: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-sidebar")
        .sheet(item: editorBinding) { _ in
            ProjectEditorSheet(controller: controller)
        }
        .alert(String(localized: "프로젝트를 삭제할까요?"), isPresented: deleteAlertBinding) {
            Button(String(localized: "취소"), role: .cancel) {
                controller.cancelDelete()
            }
            Button(String(localized: "삭제"), role: .destructive) {
                controller.confirmDelete()
            }
            .accessibilityIdentifier("project-delete-confirm")
        } message: {
            Text(String(localized: "폴더는 삭제되지 않으며 열려 있는 탭은 미분류 workspace로 이동합니다."))
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "프로젝트"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(action: onHide) {
                Label(String(localized: "왼쪽 사이드바 숨기기"), systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "왼쪽 사이드바 숨기기"))
            .accessibilityIdentifier("sidebar.left")

            Button(action: chooseDirectoryForAdd) {
                Label(String(localized: "프로젝트 추가"), systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "프로젝트 추가"))
            .accessibilityIdentifier("project-sidebar-add")
        }
        .padding(.horizontal, 12)
        .frame(height: ShellChromeMetrics.headerHeight)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            unscopedRow
            Divider()

            if projectStore.projects.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "프로젝트 없음"), systemImage: "folder.badge.plus")
                } description: {
                    Text(String(localized: "작업할 폴더를 프로젝트로 추가하세요."))
                } actions: {
                    Button(String(localized: "프로젝트 추가"), action: chooseDirectoryForAdd)
                        .accessibilityIdentifier("project-sidebar-empty-add")
                }
                .accessibilityIdentifier("project-sidebar-empty")
            } else {
                List {
                    ForEach(projectStore.projects) { project in
                        projectRow(project)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        _ = controller.moveProjects(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var unscopedRow: some View {
        Button {
            controller.selectUnscoped()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(appColors?.accent ?? Color.accentColor)
                    .frame(width: 16)

                Text(String(localized: "미분류"))
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(selectionBackground(for: .unscoped))
        .accessibilityIdentifier("project-sidebar-row-unscoped")
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Button {
                controller.select(project)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appColors?.accent ?? Color.accentColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Text(project.path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project-sidebar-row-\(project.id.uuidString)")

            Button {
                controller.beginEdit(project)
            } label: {
                Label(String(localized: "프로젝트 편집"), systemImage: "pencil")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "프로젝트 편집"))
            .accessibilityIdentifier("project-sidebar-edit-\(project.id.uuidString)")

            Button {
                controller.requestDelete(project)
            } label: {
                Label(String(localized: "프로젝트 삭제"), systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "프로젝트 삭제"))
            .accessibilityIdentifier("project-sidebar-delete-\(project.id.uuidString)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selectionBackground(for: .project(project.id)))
        .contextMenu {
            Button(String(localized: "프로젝트 편집")) {
                controller.beginEdit(project)
            }
            Button(String(localized: "프로젝트 삭제"), role: .destructive) {
                controller.requestDelete(project)
            }
        }
    }

    private func selectionBackground(for workspaceID: TabWorkspaceID) -> Color {
        guard activeWorkspaceID == workspaceID else { return Color.clear }
        return (appColors?.accent ?? Color.accentColor).opacity(0.14)
    }

    private var editorBinding: Binding<ProjectEditorState?> {
        Binding(
            get: { controller.editor },
            set: { newValue in
                if newValue == nil {
                    controller.cancelEditor()
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.deleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    controller.cancelDelete()
                }
            }
        )
    }

    private func chooseDirectoryForAdd() {
        guard let directoryURL = chooseDirectory(
            title: String(localized: "프로젝트 폴더 선택"),
            prompt: String(localized: "선택")
        ) else { return }
        controller.beginAdd(directoryURL: directoryURL)
    }
}

@MainActor
private struct ProjectEditorSheet: View {
    var controller: ProjectSidebarController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fields
        }
        .frame(minWidth: 440)
        .accessibilityIdentifier("project-editor")
        .alert(String(localized: "프로젝트를 저장할 수 없습니다."), isPresented: failureBinding) {
            Button(String(localized: "확인")) {
                controller.dismissEditorFailure()
            }
        } message: {
            Text(String(localized: "이름과 폴더를 확인하세요. 같은 폴더는 한 번만 추가할 수 있습니다."))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(editorTitle)
                .font(.system(size: 13, weight: .bold))

            Spacer(minLength: 0)

            Button(String(localized: "취소")) {
                controller.cancelEditor()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("project-editor-cancel")

            Button(String(localized: "저장")) {
                controller.saveEditor()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("project-editor-save")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var fields: some View {
        Form {
            TextField(String(localized: "이름"), text: nameBinding)
                .accessibilityIdentifier("project-editor-name")

            HStack(spacing: 8) {
                TextField(String(localized: "경로"), text: pathBinding)
                    .accessibilityIdentifier("project-editor-path")

                Button(String(localized: "폴더 선택…")) {
                    chooseReplacementDirectory()
                }
                .accessibilityIdentifier("project-editor-choose-folder")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var editorTitle: String {
        guard let editor = controller.editor else { return String(localized: "프로젝트 편집") }
        switch editor.mode {
        case .add:
            return String(localized: "프로젝트 추가")
        case .edit:
            return String(localized: "프로젝트 편집")
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { controller.editor?.name ?? "" },
            set: { controller.setEditorName($0) }
        )
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { controller.editor?.directoryURL.path ?? "" },
            set: { controller.setEditorDirectory(URL(fileURLWithPath: $0, isDirectory: true)) }
        )
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: { controller.editor?.failure == .storeRejected },
            set: { isPresented in
                if !isPresented {
                    controller.dismissEditorFailure()
                }
            }
        )
    }

    private func chooseReplacementDirectory() {
        guard let directoryURL = chooseDirectory(
            title: String(localized: "프로젝트 폴더 선택"),
            prompt: String(localized: "선택")
        ) else { return }
        controller.setEditorDirectory(directoryURL)
    }
}

@MainActor
private func chooseDirectory(title: String, prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = prompt
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
}
