import SwiftUI

struct TemplatePicker: View {
    let onApply: (String) -> Void
    let onDismiss: () -> Void

    @State private var selectedTemplate: Template? = nil
    @State private var variableValues: [String: String] = [:]

    var body: some View {
        NavigationSplitView {
            templateList
        } detail: {
            if let template = selectedTemplate {
                variableForm(for: template)
            } else {
                placeholderDetail
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: - 템플릿 목록 (사이드바)

    private var templateList: some View {
        List(BuiltInTemplates.all, selection: $selectedTemplate) { template in
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
            .tag(template as Template?)
        }
        .navigationTitle("템플릿 선택")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .onChange(of: selectedTemplate) { _, newTemplate in
            variableValues = [:]
            if let template = newTemplate {
                for variable in template.variables {
                    if !variable.defaultValue.isEmpty {
                        variableValues[variable.name] = variable.defaultValue
                    }
                }
            }
        }
    }

    // MARK: - 변수 입력 폼 (디테일)

    private func variableForm(for template: Template) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(template.name)
                        .font(.title2)
                        .bold()

                    Text(template.description)
                        .foregroundStyle(.secondary)

                    Divider()

                    if template.variables.isEmpty {
                        Text("이 템플릿에는 변수가 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(template.variables, id: \.name) { variable in
                            variableField(variable)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("취소") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("적용") {
                    let rendered = TemplateEngine.render(template, variables: variableValues)
                    onApply(rendered)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    private func variableField(_ variable: TemplateVariable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(variable.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("(\(variable.description))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if variable.placeholder.contains("\n") {
                TextEditor(text: Binding(
                    get: { variableValues[variable.name] ?? "" },
                    set: { variableValues[variable.name] = $0 }
                ))
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            } else {
                TextField(variable.placeholder, text: Binding(
                    get: { variableValues[variable.name] ?? "" },
                    set: { variableValues[variable.name] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - 빈 상태

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("왼쪽에서 템플릿을 선택하세요")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Template에 Equatable 준수 추가 (List selection용)
extension Template: Equatable {
    static func == (lhs: Template, rhs: Template) -> Bool {
        lhs.id == rhs.id
    }
}

extension Template: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
