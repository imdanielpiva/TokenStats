import CodexBarCore
import SwiftUI

/// Main content view for the Usage History window.
struct UsageHistoryWindow: View {
    @State private var store = UsageHistoryStore()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: self.$columnVisibility) {
            UsageHistorySidebar(store: self.store)
        } detail: {
            UsageHistoryDetailView(store: self.store)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await self.store.refreshCurrentProvider()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(self.store.isLoading)
                .help("Refresh data for current provider")
            }
        }
        .task {
            await self.store.loadCurrentProviderIfNeeded()
        }
    }
}

/// Sidebar showing provider list.
struct UsageHistorySidebar: View {
    @Bindable var store: UsageHistoryStore

    var body: some View {
        List(selection: self.$store.selectedProvider) {
            ForEach(UsageHistoryProvider.allCases) { provider in
                UsageHistorySidebarRow(
                    provider: provider,
                    isSelected: self.store.selectedProvider == provider,
                    isLoading: self.store.loadingProvider == provider)
                    .tag(provider)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Providers")
        .frame(minWidth: 180)
        .onChange(of: self.store.selectedProvider) { _, newProvider in
            // Clear model filter when switching providers
            self.store.selectedModels = []
            Task {
                await self.store.loadData(for: newProvider)
            }
        }
    }
}

/// Row in the provider sidebar.
struct UsageHistorySidebarRow: View {
    let provider: UsageHistoryProvider
    let isSelected: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            self.providerIcon
                .frame(width: 20, height: 20)

            Text(self.provider.displayName)
                .font(.body)

            Spacer()

            if self.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let nsImage = ProviderBrandIcon.image(for: self.provider.usageProvider) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}

/// Detail view showing charts for selected provider.
struct UsageHistoryDetailView: View {
    @Bindable var store: UsageHistoryStore

    var body: some View {
        VStack(spacing: 0) {
            // Top controls bar
            HStack {
                TimePeriodPicker(selection: self.$store.selectedPeriod)

                Spacer()

                if !self.store.availableModels.isEmpty {
                    ModelFilterPicker(
                        availableModels: self.store.availableModels,
                        selectedModels: self.$store.selectedModels)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content
            if self.store.isLoading && self.store.currentProviderData == nil {
                self.loadingView
            } else if let report = self.store.currentAggregatedReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        self.summarySection(report: report)
                        self.tokenChartSection(report: report)
                        self.costChartSection(report: report)
                    }
                    .padding(16)
                }
            } else if let error = self.store.lastError {
                self.errorView(error)
            } else {
                self.emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading usage history...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No usage data available")
                .font(.headline)
            Text("Usage data will appear here once you start using \(self.store.selectedProvider.displayName).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Error loading data")
                .font(.headline)
            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func summarySection(report: CostUsageAggregatedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Summary")
                    .font(.headline)

                Spacer()

                if let dateRange = self.dateRangeText(report: report) {
                    Text(dateRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                self.summaryItem(
                    title: "Total Tokens",
                    value: UsageFormatter.tokenCountString(report.totalTokens))

                if let cost = report.totalCostUSD {
                    self.summaryItem(
                        title: "Total Cost",
                        value: UsageFormatter.usdString(cost))
                }

                self.summaryItem(
                    title: "Periods",
                    value: "\(report.entries.count)")

                if !report.allModels.isEmpty {
                    self.summaryItem(
                        title: "Models",
                        value: "\(report.allModels.count)")
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

        if first.id == last.id {
            return first.periodLabel
        }
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

    private func tokenChartSection(report: CostUsageAggregatedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Usage")
                .font(.headline)

            UsageHistoryTokenChart(
                entries: report.entries,
                provider: self.store.selectedProvider)
                .frame(height: 200)
        }
    }

    private func costChartSection(report: CostUsageAggregatedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cost (USD)")
                    .font(.headline)

                Spacer()

                if let total = report.totalCostUSD {
                    Text("Total: \(UsageFormatter.usdString(total))")
                        .foregroundStyle(.secondary)
                }
            }

            UsageHistoryCostChart(
                entries: report.entries,
                provider: self.store.selectedProvider)
                .frame(height: 200)
        }
    }
}

#Preview {
    UsageHistoryWindow()
        .frame(width: 900, height: 650)
}
