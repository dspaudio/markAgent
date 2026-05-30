import SwiftUI

struct AgentTimelineSidebarView: View {
    var store: AgentTimelineStore

    var body: some View {
        Group {
            if store.events.isEmpty {
                Text("아직 기록된 작업 이벤트가 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.events) { event in
                            AgentTimelineEventRow(event: event)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct AgentTimelineEventRow: View {
    let event: AgentTimelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.kind.tint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(event.timestamp, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension AgentTimelineEventKind {
    var systemImage: String {
        switch self {
        case .terminal:
            return "terminal"
        case .markdown:
            return "doc.text"
        case .gitDiff:
            return "arrow.left.arrow.right.circle"
        case .commit:
            return "number.square"
        }
    }

    var tint: Color {
        switch self {
        case .terminal:
            return .green
        case .markdown:
            return .blue
        case .gitDiff:
            return .orange
        case .commit:
            return .purple
        }
    }
}
