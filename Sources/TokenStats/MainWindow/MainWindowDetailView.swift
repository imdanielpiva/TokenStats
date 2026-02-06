import SwiftUI
import TokenStatsCore

/// Detail view showing usage cards and charts for a selected provider.
struct MainWindowDetailView: View {
    let provider: UsageProvider
    @Bindable var usageStore: UsageStore
    @Bindable var settings: SettingsStore

    @State private var historyStore = UsageHistoryStore()
    @State private var hasLoadedHistory = false

    private var metadata: ProviderMetadata {
        ProviderDescriptorRegistry.descriptor(for: self.provider).metadata
    }

    private var historyProvider: UsageHistoryProvider? {
        UsageHistoryProvider.allCases.first { $0.usageProvider == self.provider }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                self.headerSection
                self.usageCardSection
                self.chartsSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: self.provider) { _, newProvider in
            self.hasLoadedHistory = false
            if let historyProvider = UsageHistoryProvider.allCases.first(where: { $0.usageProvider == newProvider }) {
                self.historyStore.selectedProvider = historyProvider
                Task {
                    await self.historyStore.loadData(for: historyProvider)
                    self.hasLoadedHistory = true
                }
            }
        }
        .task {
            if let historyProvider = self.historyProvider {
                self.historyStore.selectedProvider = historyProvider
                await self.historyStore.loadData(for: historyProvider)
                self.hasLoadedHistory = true
            }
        }
        .onChange(of: self.usageStore.isRefreshing) { oldValue, newValue in
            // When a refresh cycle completes, reload history data to keep charts current.
            if oldValue && !newValue, let historyProvider = self.historyProvider {
                Task {
                    await self.historyStore.loadData(for: historyProvider, forceRefresh: true)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            self.providerIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.metadata.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                self.subtitleText
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if self.usageStore.refreshingProviders.contains(self.provider) {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let nsImage = ProviderBrandIcon.image(for: self.provider) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let error = self.usageStore.error(for: self.provider) {
            Text(error)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if let snapshot = self.usageStore.snapshot(for: self.provider) {
            Text("Updated \(UsageFormatter.updatedString(from: snapshot.updatedAt))")
        } else if self.usageStore.refreshingProviders.contains(self.provider) {
            Text("Refreshing...")
        } else {
            Text("No data yet")
        }
    }

    // MARK: - Usage Card

    private var usageCardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = self.usageStore.snapshot(for: self.provider) {
                ProviderUsageCardView(
                    provider: self.provider,
                    snapshot: snapshot,
                    usageStore: self.usageStore,
                    settings: self.settings)
            } else if self.usageStore.refreshingProviders.contains(self.provider) {
                self.loadingPlaceholder
            } else {
                self.emptyUsagePlaceholder
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading usage data...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private var emptyUsagePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No usage data available")
                .font(.headline)
            Text("Usage will appear once you start using \(self.metadata.displayName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartsSection: some View {
        if self.historyProvider != nil {
            VStack(alignment: .leading, spacing: 16) {
                Divider()
                    .padding(.vertical, 8)

                self.chartsHeader

                if self.historyStore.isLoading && self.historyStore.currentProviderData == nil {
                    self.chartsLoadingView
                } else if let report = self.historyStore.currentAggregatedReport, !report.entries.isEmpty {
                    self.chartsContent(report: report)
                } else if !self.hasLoadedHistory {
                    self.chartsLoadingView
                } else {
                    self.chartsEmptyView
                }
            }
        }
    }

    private var chartsHeader: some View {
        HStack {
            Text("Usage History")
                .font(.headline)

            Spacer()

            TimePeriodPicker(selection: self.$historyStore.selectedPeriod)

            if !self.historyStore.availableModels.isEmpty {
                ModelFilterPicker(
                    availableModels: self.historyStore.availableModels,
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
            // Row 1: Summary + Projected Spend (side by side, equal height)
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    self.summarySection(report: report)
                    if self.historyStore.selectedPeriod == .day && report.totalCostUSD != nil {
                        UsageHistoryProjectionCard(
                            entries: report.entries,
                            provider: self.historyStore.selectedProvider)
                    }
                }
            }

            // Row 2: Streaks + Activity (side by side, daily only with >7 entries)
            if self.historyStore.selectedPeriod == .day && report.entries.count > 7 {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        self.streakSection
                        self.chartSection(title: "Activity") {
                            UsageHistoryCalendarHeatmap(
                                entries: report.entries,
                                provider: self.historyStore.selectedProvider)
                        }
                    }
                }
            }

            // Row 3: Insights
            if !report.entries.isEmpty {
                self.chartSection(title: "Insights") {
                    UsageHistoryFunStats(entries: report.entries, report: report)
                }
            }

            // Row 4: Token Usage
            self.chartSection(title: "Token Usage") {
                UsageHistoryTokenChart(
                    entries: report.entries,
                    provider: self.historyStore.selectedProvider)
                    .frame(height: 200)
            }

            // Row 5: Cost (USD)
            if report.totalCostUSD != nil {
                self.chartSection(title: "Cost (USD)", subtitle: "Total: \(UsageFormatter.usdString(report.totalCostUSD ?? 0))") {
                    UsageHistoryCostChart(
                        entries: report.entries,
                        provider: self.historyStore.selectedProvider)
                        .frame(height: 200)
                }
            }

            // Row 6: Input vs Output Tokens
            self.tokenBreakdownSection(report: report)

            // Row 7: Cumulative Spend
            if report.totalCostUSD != nil && report.entries.count > 1 {
                self.chartSection(title: "Cumulative Spend", subtitle: "Total: \(UsageFormatter.usdString(report.totalCostUSD ?? 0))") {
                    UsageHistoryCumulativeSpendChart(
                        entries: report.entries,
                        provider: self.historyStore.selectedProvider)
                        .frame(height: 200)
                }
            }

            // Row 8: Cumulative Tokens
            if report.entries.count > 1 {
                self.chartSection(
                    title: "Cumulative Tokens",
                    subtitle: "Total: \(UsageFormatter.tokenCountString(report.totalTokens))")
                {
                    UsageHistoryCumulativeTokenChart(
                        entries: report.entries,
                        provider: self.historyStore.selectedProvider)
                        .frame(height: 200)
                }
            }

            // Row 9: Week Comparison (daily period only)
            if self.historyStore.selectedPeriod == .day && report.entries.count > 7 {
                self.chartSection(title: "Week Comparison") {
                    UsageHistoryWeekComparison(entries: report.entries)
                }
            }

            // Row 10: Usage by Day of Week (daily period only)
            if self.historyStore.selectedPeriod == .day && report.entries.count > 7 {
                self.chartSection(title: "Usage by Day of Week") {
                    UsageHistoryWeekdayChart(
                        entries: report.entries,
                        provider: self.historyStore.selectedProvider)
                        .frame(height: 180)
                }
            }
        }
    }

    // MARK: - Streaks Section

    @ViewBuilder
    private var streakSection: some View {
        let streaks = self.historyStore.modelStreaks.filter { $0.currentStreak > 0 || $0.longestStreak > 1 }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

                // Show ratio in header
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
                provider: self.historyStore.selectedProvider)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
