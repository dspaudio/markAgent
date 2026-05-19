import SwiftUI

struct TabItemView: View {
    let tab: any MarkAgentTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            if tab.isDirty {
                Text("●")
                    .font(.system(size: 8))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }

            if tab.isClosable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .padding(2)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isActive ? 1.0 : 0.0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(height: 2),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
