import SwiftUI
import TokenStatsCore

/// Detail view showing combined usage across all providers.
struct MainWindowCombinedDetailView: View {
    @Bindable var usageStore: UsageStore
    @Bindable var settings: SettingsStore

    @State private var historyStore = UsageHistoryStore()
    @State private var hasLoadedHistory = false

    private var combinedSnapshot: CostUsageTokenSnapshot? {
        self.usageStore.combinedTokenSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                self.headerSection
                self.costSummarySection
                self.chartsSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await self.historyStore.loadCombinedData()
            self.hasLoadedHistory = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("All Providers")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Combined usage across all enabled providers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if self.historyStore.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    // MARK: - Cost Summary

    private var costSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = self.combinedSnapshot {
                VStack(alignment: .leading, spacing: 12) {
                    // Cost cards
                    HStack(spacing: 16) {
                        if let sessionCost = snapshot.sessionCostUSD {
                            self.costCard(title: "Today", value: UsageFormatter.usdString(sessionCost))
                        }
                        if let totalCost = snapshot.last30DaysCostUSD {
                            self.costCard(title: "Last 30 Days", value: UsageFormatter.usdString(totalCost))
                        }
                    }

                    // Token cards
                    HStack(spacing: 16) {
                        if let sessionTokens = snapshot.sessionTokens {
                            self.tokenCard(title: "Tokens Today", value: UsageFormatter.tokenCountString(sessionTokens))
                        }
                        if let totalTokens = snapshot.last30DaysTokens {
                            self.tokenCard(title: "Tokens (30 Days)", value: UsageFormatter.tokenCountString(totalTokens))
                        }
                    }

                    // Provider breakdown
                    self.providerBreakdownSection
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
        }
    }

    private func costCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func tokenCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                Text("tokens")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private var providerBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider Breakdown")
                .font(.caption)
                .foregroundStyle(.secondary)

            let providers: [UsageProvider] = [.claude, .codex, .vertexai, .amp]
            ForEach(providers.filter { self.usageStore.isEnabled($0) }, id: \.self) { provider in
                if let snapshot = self.usageStore.tokenSnapshots[provider] {
                    self.providerRow(provider: provider, snapshot: snapshot)
                }
            }
        }
    }

    private func providerRow(provider: UsageProvider, snapshot: CostUsageTokenSnapshot) -> some View {
        let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
        return HStack {
            if let nsImage = ProviderBrandIcon.image(for: provider) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            Text(metadata.displayName)
                .font(.subheadline)

            Spacer()

            if let cost = snapshot.last30DaysCostUSD {
                Text(UsageFormatter.usdString(cost))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.vertical, 8)

            self.chartsHeader

            if self.historyStore.isLoading && self.historyStore.combinedData == nil {
                self.chartsLoadingView
            } else if let report = self.historyStore.combinedAggregatedReport, !report.entries.isEmpty {
                self.chartsContent(report: report)
            } else if !self.hasLoadedHistory {
                self.chartsLoadingView
            } else {
                self.chartsEmptyView
            }
        }
    }

    private var chartsHeader: some View {
        HStack {
            Text("Usage History")
                .font(.headline)

            Spacer()

            TimePeriodPicker(selection: self.$historyStore.selectedPeriod)

            if !self.historyStore.combinedAvailableModels.isEmpty {
                ModelFilterPicker(
                    availableModels: self.historyStore.combinedAvailableModels,
                    selectedModels: self.$historyStore.selectedModels)
            }
        }
    }

    private var chartsLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading usage history...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var chartsEmptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No historical data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private func chartsContent(report: CostUsageAggregatedReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary section
            self.summarySection(report: report)

            // Streaks section
            self.streakSection

            // Fun stats / Insights
            if !report.entries.isEmpty {
                self.chartSection(title: "Insights") {
                    UsageHistoryFunStats(entries: report.entries, report: report)
                }
            }

            // Week comparison (daily period only)
            if self.historyStore.selectedPeriod == .day && report.entries.count > 7 {
                self.chartSection(title: "Week Comparison") {
                    UsageHistoryWeekComparison(entries: report.entries)
                }
            }

            // Calendar heatmap (daily period only)
            if self.historyStore.selectedPeriod == .day && report.entries.count > 7 {
                self.chartSection(title: "Activity") {
                    UsageHistoryCalendarHeatmap(
                        entries: report.entries,
                        provider: .claude) // Use claude styling for combined
                }
            }

            // Token chart
            self.chartSection(title: "Token Usage") {
                UsageHistoryTokenChart(
                    entries: report.entries,
                    provider: .claude) // Use claude styling for combined
                    .frame(height: 200)
            }

            // Input vs Output tokens breakdown
            self.tokenBreakdownSection(report: report)

            // Usage by day of week (daily period only)
            if self.historyStore.selectedPeriod == .day && report.entries.count > 7 {
                self.chartSection(title: "Usage by Day of Week") {
                    UsageHistoryWeekdayChart(
                        entries: report.entries,
                        provider: .claude) // Use claude styling for combined
                        .frame(height: 180)
                }
            }

            // Cost chart (if available)
            if report.totalCostUSD != nil {
                self.chartSection(
                    title: "Cost (USD)",
                    subtitle: "Total: \(UsageFormatter.usdString(report.totalCostUSD ?? 0))")
                {
                    UsageHistoryCostChart(
                        entries: report.entries,
                        provider: .claude) // Use claude styling for combined
                        .frame(height: 200)
                }
            }

            // Cumulative spend (when cost data available)
            if report.totalCostUSD != nil && report.entries.count > 1 {
                self.chartSection(
                    title: "Cumulative Spend",
                    subtitle: "Total: \(UsageFormatter.usdString(report.totalCostUSD ?? 0))")
                {
                    UsageHistoryCumulativeSpendChart(
                        entries: report.entries,
                        provider: .claude) // Use claude styling for combined
                        .frame(height: 200)
                }
            }

            // Cumulative tokens (when >1 entry)
            if report.entries.count > 1 {
                self.chartSection(
                    title: "Cumulative Tokens",
                    subtitle: "Total: \(UsageFormatter.tokenCountString(report.totalTokens))")
                {
                    UsageHistoryCumulativeTokenChart(
                        entries: report.entries,
                        provider: .claude) // Use claude styling for combined
                        .frame(height: 200)
                }
            }
        }
    }

    // MARK: - Streaks Section

    @ViewBuilder
    private var streakSection: some View {
        let streaks = self.historyStore.combinedModelStreaks.filter { $0.currentStreak > 0 || $0.longestStreak > 1 }
        if !streaks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Streaks")
                    .font(.subheadline)
                    .fontWeight(.medium)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12),
                ], spacing: 12) {
                    ForEach(streaks.prefix(6)) { streak in
                        self.streakCard(streak)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func streakCard(_ streak: ModelStreak) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UsageFormatter.modelDisplayName(streak.modelName))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if streak.currentStreak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(streak.currentStreak)d")
                            .fontWeight(.semibold)
                    }
                }

                if streak.longestStreak > streak.currentStreak {
                    HStack(spacing: 2) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                        Text("\(streak.longestStreak)d")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Token Breakdown Section

    private func tokenBreakdownSection(report: CostUsageAggregatedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input vs Output Tokens")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                let totalInput = report.totalInputTokens
                let totalOutput = report.totalOutputTokens
                if totalInput + totalOutput > 0 {
                    let outputRatio = Double(totalOutput) / Double(totalInput + totalOutput) * 100
                    Text("\(Int(outputRatio))% output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            UsageHistoryTokenBreakdownChart(
                entries: report.entries,
                provider: .claude) // Use claude styling for combined
                .frame(height: 200)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func summarySection(report: CostUsageAggregatedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let dateRange = self.dateRangeText(report: report) {
                    Text(dateRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                self.summaryItem(title: "Total Tokens", value: UsageFormatter.tokenCountString(report.totalTokens))

                if let cost = report.totalCostUSD {
                    self.summaryItem(title: "Total Cost", value: UsageFormatter.usdString(cost))
                }

                self.summaryItem(title: "Periods", value: "\(report.entries.count)")

                if !report.allModels.isEmpty {
                    self.summaryItem(title: "Models", value: "\(report.allModels.count)")
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func dateRangeText(report: CostUsageAggregatedReport) -> String? {
        guard let first = report.entries.first,
              let last = report.entries.last else { return nil }
        if first.id == last.id { return first.periodLabel }
        return "\(first.periodLabel) - \(last.periodLabel)"
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.medium)
        }
    }

    private func chartSection(title: String, subtitle: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
