import SwiftUI
import TokenStatsCore

/// Usage card view for the main window, adapted from UsageMenuCardView.
/// Displays usage metrics without menu-specific styling.
struct ProviderUsageCardView: View {
    let provider: UsageProvider
    let snapshot: UsageSnapshot
    @Bindable var usageStore: UsageStore
    @Bindable var settings: SettingsStore

    private var metadata: ProviderMetadata {
        ProviderDescriptorRegistry.descriptor(for: self.provider).metadata
    }

    private var branding: ProviderBranding {
        ProviderDescriptorRegistry.descriptor(for: self.provider).branding
    }

    private var progressColor: Color {
        Color(red: self.branding.color.red, green: self.branding.color.green, blue: self.branding.color.blue)
    }

    private var percentStyle: UsageMenuCardView.Model.PercentStyle {
        self.settings.usageBarsShowUsed ? .used : .left
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Primary quota (session)
            if let primary = self.snapshot.primary {
                self.metricView(
                    title: self.metadata.sessionLabel,
                    window: primary,
                    detailText: self.provider == .zai ? self.zaiLimitDetailText(limit: self.snapshot.zaiUsage?.tokenLimit) : nil)
            }

            // Secondary quota (weekly)
            if let secondary = self.snapshot.secondary {
                let paceText = UsagePaceText.weekly(provider: self.provider, window: secondary, now: Date())
                self.metricView(
                    title: self.metadata.weeklyLabel,
                    window: secondary,
                    detailText: self.provider == .zai ? self.zaiLimitDetailText(limit: self.snapshot.zaiUsage?.timeLimit) : paceText)
            }

            // Tertiary quota (opus/sonnet)
            if self.metadata.supportsOpus, let tertiary = self.snapshot.tertiary {
                self.metricView(
                    title: self.metadata.opusLabel ?? "Sonnet",
                    window: tertiary,
                    detailText: nil)
            }

            // Code review (Codex only)
            if self.provider == .codex {
                if let remaining = self.usageStore.openAIDashboard?.codeReviewRemainingPercent {
                    let percent = self.settings.usageBarsShowUsed ? (100 - remaining) : remaining
                    self.simpleMetricView(
                        title: "Code review",
                        percent: percent)
                }
            }

            // Credits section (Codex)
            if self.metadata.supportsCredits {
                self.creditsSection
            }

            // Provider cost section (Claude extra usage)
            if let providerCost = self.snapshot.providerCost, providerCost.limit > 0 {
                self.providerCostSection(cost: providerCost)
            }

            // Amp credits section
            if self.provider == .amp {
                self.ampCreditsSection
            }

            // Token cost section
            if self.settings.isCostUsageEffectivelyEnabled(for: self.provider) {
                self.tokenCostSection
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Metric Views

    private func metricView(title: String, window: RateWindow, detailText: String?) -> some View {
        let percent = self.settings.usageBarsShowUsed ? window.usedPercent : window.remainingPercent

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.medium)

            WindowProgressBar(percent: percent, tint: self.progressColor)

            HStack(alignment: .firstTextBaseline) {
                Text(self.percentLabel(percent: percent))
                    .font(.footnote)

                Spacer()

                if let resetText = UsageFormatter.resetLine(for: window, style: self.settings.resetTimeDisplayStyle, now: Date()) {
                    Text(resetText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let detail = detailText {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func simpleMetricView(title: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.medium)

            WindowProgressBar(percent: percent, tint: self.progressColor)

            Text(self.percentLabel(percent: percent))
                .font(.footnote)
        }
    }

    private func percentLabel(percent: Double) -> String {
        let clamped = min(100, max(0, percent))
        return String(format: "%.0f%% %@", clamped, self.percentStyle.labelSuffix)
    }

    // MARK: - Credits Section

    @ViewBuilder
    private var creditsSection: some View {
        if let credits = self.usageStore.credits {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Credits")
                    .font(.body)
                    .fontWeight(.medium)

                let percentLeft = min(100, max(0, (credits.remaining / 1000) * 100))
                WindowProgressBar(percent: percentLeft, tint: self.progressColor)

                HStack(alignment: .firstTextBaseline) {
                    Text(UsageFormatter.creditsString(from: credits.remaining))
                        .font(.caption)
                    Spacer()
                    Text("\(UsageFormatter.tokenCountString(1000)) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let error = self.usageStore.lastCreditsError, !error.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Credits")
                    .font(.body)
                    .fontWeight(.medium)

                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Amp Credits Section

    @ViewBuilder
    private var ampCreditsSection: some View {
        if let ampCredits = self.snapshot.ampCredits {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily Credits")
                    .font(.body)
                    .fontWeight(.medium)

                // Progress bar showing remaining credits (green when high, red when low)
                let percentRemaining = min(100, max(0, (ampCredits.remainingToday / 10.0) * 100))
                WindowProgressBar(percent: percentRemaining, tint: self.ampCreditsTint(percentRemaining: percentRemaining))

                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "$%.2f remaining", ampCredits.remainingToday))
                        .font(.footnote)
                    Spacer()
                    Text("+$0.42/hr")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Usage stats
            VStack(alignment: .leading, spacing: 6) {
                Text("Usage")
                    .font(.body)
                    .fontWeight(.medium)

                let todayTokens = UsageFormatter.tokenCountString(ampCredits.tokensToday)
                Text("Today: \(String(format: "$%.2f", ampCredits.spentToday)) · \(todayTokens) tokens")
                    .font(.caption)

                let totalTokens = UsageFormatter.tokenCountString(ampCredits.tokensTotal)
                Text("Total: \(String(format: "$%.2f", ampCredits.spentTotal)) · \(totalTokens) tokens")
                    .font(.caption)

                if let avgCredits = ampCredits.averageCreditsPerThread,
                   let avgTokens = ampCredits.averageTokensPerThread
                {
                    let avgTokensStr = UsageFormatter.tokenCountString(avgTokens)
                    Text("Avg per thread: \(String(format: "$%.2f", avgCredits)) · \(avgTokensStr) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ampCreditsTint(percentRemaining: Double) -> Color {
        if percentRemaining > 50 {
            return .green
        } else if percentRemaining > 20 {
            return .yellow
        } else {
            return .red
        }
    }

    // MARK: - Provider Cost Section

    private func providerCostSection(cost: ProviderCostSnapshot) -> some View {
        let title: String
        let used: String
        let limit: String

        if cost.currencyCode == "Quota" {
            title = "Quota usage"
            used = String(format: "%.0f", cost.used)
            limit = String(format: "%.0f", cost.limit)
        } else {
            title = "Extra usage"
            used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            limit = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
        }

        let percentUsed = min(100, max(0, (cost.used / cost.limit) * 100))
        let periodLabel = cost.period ?? "This month"

        return Group {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                WindowProgressBar(percent: percentUsed, tint: self.progressColor)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(periodLabel): \(used) / \(limit)")
                        .font(.footnote)
                    Spacer()
                    Text(String(format: "%.0f%% used", percentUsed))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Token Cost Section

    @ViewBuilder
    private var tokenCostSection: some View {
        if let tokenSnapshot = self.usageStore.tokenSnapshot(for: self.provider) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Cost")
                    .font(.body)
                    .fontWeight(.medium)

                let sessionCost = tokenSnapshot.sessionCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
                let sessionTokens = tokenSnapshot.sessionTokens.map { UsageFormatter.tokenCountString($0) }

                if let sessionTokens {
                    Text("Today: \(sessionCost) · \(sessionTokens) tokens")
                        .font(.caption)
                } else {
                    Text("Today: \(sessionCost)")
                        .font(.caption)
                }

                let monthCost = tokenSnapshot.last30DaysCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
                let fallbackTokens = tokenSnapshot.daily.compactMap(\.totalTokens).reduce(0, +)
                let monthTokensValue = tokenSnapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
                let monthTokens = monthTokensValue.map { UsageFormatter.tokenCountString($0) }

                if let monthTokens {
                    Text("Last 30 days: \(monthCost) · \(monthTokens) tokens")
                        .font(.caption)
                } else {
                    Text("Last 30 days: \(monthCost)")
                        .font(.caption)
                }
            }
        } else if let error = self.usageStore.tokenError(for: self.provider), !error.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Cost")
                    .font(.body)
                    .fontWeight(.medium)

                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Helpers

    private func zaiLimitDetailText(limit: ZaiLimitEntry?) -> String? {
        guard let limit else { return nil }
        let currentStr = UsageFormatter.tokenCountString(limit.currentValue)
        let usageStr = UsageFormatter.tokenCountString(limit.usage)
        let remainingStr = UsageFormatter.tokenCountString(limit.remaining)
        return "\(currentStr) / \(usageStr) (\(remainingStr) remaining)"
    }
}

// MARK: - Window Progress Bar

/// Progress bar for main window context (no menu highlighting).
private struct WindowProgressBar: View {
    let percent: Double
    let tint: Color

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * self.clamped / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor))
                Capsule()
                    .fill(self.tint)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Usage")
        .accessibilityValue("\(Int(self.clamped)) percent")
    }
}
