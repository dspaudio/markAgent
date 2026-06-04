import SwiftUI

struct TabItemView: View {
    let tab: any MarkAgentTab
    let isActive: Bool
    let groupShortcutNumber: Int?
    let showsGroupShortcut: Bool
    let showsGroupUnderline: Bool
    let isTuckedBehindParent: Bool
    let castsTrailingShadow: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(tab.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? primaryColor : secondaryColor)

                if tab.isDirty {
                    Text("●")
                        .font(.system(size: 8))
                        .foregroundStyle(isActive ? primaryColor : secondaryColor)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            trailingActionSlot
        }
        .frame(width: tabWidth)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .opacity(isTuckedBehindParent ? 0.82 : 1.0)
        .background(tabBackground)
        .overlay(
            Rectangle()
                .fill(bottomLineColor)
                .frame(height: showsGroupUnderline ? 3 : 2),
            alignment: .bottom
        )
        .clipped()
        .overlay(trailingShadowOverlay, alignment: .trailing)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTuckedBehindParent)
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var primaryColor: Color {
        appColors?.foreground ?? Color.primary
    }

    private var secondaryColor: Color {
        appColors?.secondaryForeground ?? Color.secondary
    }

    private var activeBackground: Color {
        appColors?.panel ?? Color(nsColor: .controlBackgroundColor)
    }

    private var tuckedBackground: Color {
        (appColors?.panel ?? Color(nsColor: .controlBackgroundColor)).opacity(0.72)
    }

    private var coverBackground: Color {
        appColors?.background ?? Color(nsColor: .windowBackgroundColor)
    }

    private var tabBackground: Color {
        if isActive {
            return activeBackground
        }
        if isTuckedBehindParent {
            return tuckedBackground
        }
        if castsTrailingShadow {
            return coverBackground
        }
        return Color.clear
    }

    private var groupAccentColor: Color {
        guard groupShortcutNumber != nil else { return Color.clear }
        return appColors?.accent ?? Color.accentColor
    }

    private var bottomLineColor: Color {
        if isActive && showsGroupUnderline {
            return groupAccentColor
        }
        return isActive ? (appColors?.accent ?? Color.accentColor) : Color.clear
    }

    private var groupBadgeColor: Color {
        groupAccentColor.opacity(0.12)
    }

    private var activeGroupBadgeColor: Color {
        groupAccentColor.opacity(0.22)
    }

    private var groupTextColor: Color {
        appColors?.accent ?? Color.accentColor
    }

    private var activeGroupTextColor: Color {
        appColors?.foreground ?? Color.primary
    }

    private var tabWidth: CGFloat {
        if isTuckedBehindParent {
            return 78
        }

        let dirtyWidth: Double = tab.isDirty ? 10 : 0
        let estimatedTitleWidth = Double(tab.title.count) * 7.5
        return CGFloat(max(86, min(168, estimatedTitleWidth + dirtyWidth + 56)))
    }

    @ViewBuilder
    private var trailingShadowOverlay: some View {
        if castsTrailingShadow {
            LinearGradient(
                colors: [Color.black.opacity(0.24), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 14)
            .offset(x: 14)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var trailingActionSlot: some View {
        ZStack(alignment: .trailing) {
            if let groupShortcutNumber {
                Text("⌘\(groupShortcutNumber)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? activeGroupTextColor : groupTextColor)
                    .frame(width: 28, height: 16)
                    .background(
                        Capsule()
                            .fill(isActive ? activeGroupBadgeColor : groupBadgeColor)
                    )
                    .opacity(showsGroupShortcut && !isHovering ? 1.0 : 0.0)
            }

            if tab.isClosable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .padding(2)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .opacity(isHovering ? 1.0 : 0.0)
            }
        }
        .frame(width: 28, height: 16, alignment: .trailing)
    }
}
