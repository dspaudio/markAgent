import SwiftUI

@MainActor
struct BottomStatusBar: View {
    var subscriptionStatus: SubscriptionStatusModel
    var systemStatus: SystemStatusModel
    var onOpenSettings: () -> Void

    @State private var isShowingUsage = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isShowingUsage = true
            } label: {
                if subscriptionStatus.enabledProviders.isEmpty {
                    Label("AI 0", systemImage: "waveform.path.ecg")
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            ForEach(subscriptionStatus.enabledProviders) { provider in
                                providerSummary(provider, compact: false)
                            }
                        }

                        Label(
                            "AI \(subscriptionStatus.enabledProviders.count)",
                            systemImage: "waveform.path.ecg"
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("status-usage")
            .popover(isPresented: $isShowingUsage, arrowEdge: .bottom) {
                UsagePopover(
                    subscriptionStatus: subscriptionStatus,
                    onOpenSettings: {
                        isShowingUsage = false
                        onOpenSettings()
                    }
                )
            }

            Spacer(minLength: 8)

            Button {
                Task {
                    await systemStatus.setCaffeinateEnabled(!systemStatus.isCaffeinateEnabled)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer")
                    Text(systemStatus.isCaffeinateEnabled ? "On" : "Off")
                    Circle()
                        .fill(
                            systemStatus.isCaffeinateEnabled
                                ? (appColors?.accent ?? Color.accentColor)
                                : Color.secondary.opacity(0.5)
                        )
                        .frame(width: 7, height: 7)
                }
            }
            .buttonStyle(.plain)
            .help(
                systemStatus.isCaffeinateEnabled
                    ? String(localized: "MarkAgent가 소유한 절전 방지 assertion 끄기")
                    : String(localized: "MarkAgent 절전 방지 assertion 생성")
            )
            .accessibilityLabel("Caffeinate")
            .accessibilityValue(systemStatus.isCaffeinateEnabled ? "On" : "Off")
            .accessibilityIdentifier("status-caffeinate")

            HStack(spacing: 5) {
                Image(systemName: "memorychip")
                Text(memoryText)
                    .monospacedDigit()
            }
            .foregroundStyle(appColors?.foreground ?? Color.primary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("MarkAgent 메모리 사용량")
            .accessibilityValue(memoryText)
            .accessibilityIdentifier("status-memory")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(appColors?.panel ?? Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appColors?.border ?? Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .accessibilityIdentifier("status-bar")
    }

    private func providerSummary(
        _ provider: SubscriptionProvider,
        compact: Bool
    ) -> some View {
        HStack(spacing: 6) {
            ProviderBrandIcon(provider: provider, size: 14)

            if !compact {
                Text(provider.displayName)
            }

            switch subscriptionStatus.state(for: provider) {
            case .disabled:
                Text("Off")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.mini)
            case .available(let usage):
                UsageProgressBar(percent: usage.primary.usedPercent, width: 44)
                Text("\(usage.primary.usedPercent, specifier: "%.0f")%")
                    .monospacedDigit()
                Text(usage.primary.resetsAt, style: .relative)
                    .foregroundStyle(appColors?.foreground ?? Color.primary)
            case .unavailable:
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("status-usage-\(provider.rawValue)")
    }

    private var memoryText: String {
        guard let bytes = systemStatus.residentMemoryBytes else { return "—" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .memory
        )
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
}

@MainActor
struct UsagePopover: View {
    var subscriptionStatus: SubscriptionStatusModel
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Usage")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await subscriptionStatus.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(String(localized: "사용량 새로고침"))
                .accessibilityLabel("사용량 새로고침")
                .accessibilityIdentifier("status-usage-refresh")
            }
            .padding(16)

            Divider()

            if subscriptionStatus.enabledProviders.isEmpty {
                ContentUnavailableView(
                    "등록된 AI 구독이 없습니다.",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Settings에서 Claude 또는 Codex를 활성화하세요.")
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(subscriptionStatus.enabledProviders) { provider in
                        providerDetails(provider)
                        if provider != subscriptionStatus.enabledProviders.last {
                            Divider()
                        }
                    }
                }
            }

            Divider()

            Button(action: onOpenSettings) {
                Label("AI 구독 관리…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityIdentifier("status-usage-settings")
        }
        .frame(width: 420)
        .foregroundStyle(appColors?.foreground ?? Color.primary)
        .background(appColors?.elevated ?? Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("status-usage-popover")
    }

    @ViewBuilder
    private func providerDetails(_ provider: SubscriptionProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProviderBrandIcon(provider: provider, size: 18)
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                stateBadge(subscriptionStatus.state(for: provider))
            }

            switch subscriptionStatus.state(for: provider) {
            case .available(let usage):
                ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.name)
                            Spacer()
                            Text("\(window.usedPercent, specifier: "%.0f")%")
                                .monospacedDigit()
                        }
                        UsageProgressBar(percent: window.usedPercent)
                        HStack {
                            Text("Reset")
                                .foregroundStyle(secondaryTextColor)
                            Text(window.resetsAt, style: .relative)
                            Spacer()
                            Text(window.resetsAt, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(secondaryTextColor)
                        }
                        .font(.caption)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(provider.displayName) \(window.name) \(window.usedPercent, specifier: "%.0f") 퍼센트, reset \(window.resetsAt.formatted(.relative(presentation: .named)))"
                    )
                }
            case .disabled:
                Text("Settings에서 활성화할 수 있습니다.")
                    .foregroundStyle(secondaryTextColor)
            case .loading:
                ProgressView("사용량을 불러오는 중…")
                    .controlSize(.small)
            case .unavailable(let message):
                Text(message)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func stateBadge(_ state: SubscriptionProviderState) -> some View {
        switch state {
        case .disabled:
            Text("Off")
                .foregroundStyle(secondaryTextColor)
        case .loading:
            ProgressView()
                .controlSize(.mini)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(successColor)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(warningColor)
        }
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }

    private var secondaryTextColor: Color {
        appColors?.foreground ?? Color.primary
    }

    private var successColor: Color {
        appColors.map { Color(nsColor: $0.syntaxGreen) } ?? Color.green
    }

    private var warningColor: Color {
        appColors.map { Color(nsColor: $0.syntaxYellow) } ?? Color.orange
    }
}

private struct UsageProgressBar: View {
    let percent: Double
    var width: CGFloat?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalAppTheme) private var terminalAppTheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill((appColors?.foreground ?? Color.primary).opacity(0.14))
                Capsule()
                    .fill(appColors?.foreground ?? Color.primary)
                    .frame(
                        width: geometry.size.width * min(100, max(0, percent)) / 100
                    )
            }
        }
        .frame(width: width, height: 6)
        .accessibilityValue("\(percent, specifier: "%.0f") 퍼센트")
    }

    private var appColors: TerminalAppColors? {
        terminalAppTheme?.colors(for: colorScheme)
    }
}
