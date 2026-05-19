import SwiftUI

struct NewTabChooserView: View {
    var onCreateTerminal: () -> Void
    var onCreateMarkdown: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme
    
    var body: some View {
        VStack(spacing: 20) {
            Text("새 탭 만들기")
                .font(.headline)
            
            HStack(spacing: 20) {
                Button(action: onCreateTerminal) {
                    VStack(spacing: 12) {
                        Image(systemName: "terminal")
                            .font(.system(size: 32))
                        Text("터미널")
                            .font(.subheadline)
                    }
                    .frame(width: 120, height: 100)
                    .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onCreateMarkdown) {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                        Text("마크다운")
                            .font(.subheadline)
                    }
                    .frame(width: 120, height: 100)
                    .background(appColors?.panel ?? Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Button("취소", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(30)
        .background(appColors?.background ?? Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .cornerRadius(12)
        .shadow(radius: 10)
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
}
