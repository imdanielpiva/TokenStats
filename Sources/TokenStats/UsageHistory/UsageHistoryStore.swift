import TokenStatsCore
import Foundation
import Observation

/// Providers that support historical usage data.
enum UsageHistoryProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case vertexai
    case amp

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .vertexai: "VertexAI"
        case .amp: "Amp"
        }
    }

    var usageProvider: UsageProvider {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .vertexai: .vertexai
        case .amp: .amp
        }
    }
}

/// Selection state that includes optional combined view.
enum UsageHistorySelection: Hashable, Sendable {
    case provider(UsageHistoryProvider)
    case combined

    var displayName: String {
        switch self {
        case let .provider(p): p.displayName
        case .combined: "All Providers"
        }
    }

    var historyProvider: UsageHistoryProvider? {
        switch self {
        case let .provider(p): p
        case .combined: nil
        }
    }
}

/// Observable store for Usage History window state.
@Observable
@MainActor
final class UsageHistoryStore {
    // MARK: - Selection state

    var selectedProvider: UsageHistoryProvider = .claude
    var selectedPeriod: CostUsageTimePeriod = .day
    var selectedModels: Set<String> = []

    // MARK: - Data state

    private(set) var isLoading: Bool = false
    private(set) var loadingProvider: UsageHistoryProvider?
    private(set) var lastError: String?

    // Per-provider data cache
    private(set) var claudeData: ProviderHistoryData?
    private(set) var codexData: ProviderHistoryData?
    private(set) var vertexaiData: ProviderHistoryData?
    private(set) var ampData: ProviderHistoryData?
    private(set) var combinedData: ProviderHistoryData?

    // MARK: - Computed accessors

    var currentProviderData: ProviderHistoryData? {
        switch self.selectedProvider {
        case .claude: self.claudeData
        case .codex: self.codexData
        case .vertexai: self.vertexaiData
        case .amp: self.ampData
        }
    }

    var currentAggregatedReport: CostUsageAggregatedReport? {
        guard let data = self.currentProviderData else { return nil }

        // Apply model filter
        let filtered: [CostUsageDailyReport.Entry]
        if self.selectedModels.isEmpty {
            filtered = data.daily
        } else {
            filtered = CostUsageAggregator.filterByModels(data.daily, models: self.selectedModels)
        }

        return CostUsageAggregator.aggregate(daily: filtered, by: self.selectedPeriod)
    }

    var availableModels: [String] {
        guard let data = self.currentProviderData else { return [] }
        return data.allModels
    }

    var modelStreaks: [ModelStreak] {
        guard let data = self.currentProviderData else { return [] }
        return CostUsageAggregator.calculateStreaks(data.daily)
    }

    // MARK: - Data loading

    func loadData(for provider: UsageHistoryProvider, forceRefresh: Bool = false) async {
        // Skip if already loaded and not forcing refresh
        if !forceRefresh {
            switch provider {
            case .claude: if self.claudeData != nil { return }
            case .codex: if self.codexData != nil { return }
            case .vertexai: if self.vertexaiData != nil { return }
            case .amp: if self.ampData != nil { return }
            }
        }

        self.isLoading = true
        self.loadingProvider = provider
        self.lastError = nil

        defer {
            self.isLoading = false
            self.loadingProvider = nil
        }

        do {
            let data = try await self.fetchAllTimeData(for: provider)
            switch provider {
            case .claude: self.claudeData = data
            case .codex: self.codexData = data
            case .vertexai: self.vertexaiData = data
            case .amp: self.ampData = data
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func refreshCurrentProvider() async {
        await self.loadData(for: self.selectedProvider, forceRefresh: true)
    }

    func loadCurrentProviderIfNeeded() async {
        await self.loadData(for: self.selectedProvider, forceRefresh: false)
    }

    // MARK: - Combined data loading

    /// Load data for all providers and combine them.
    func loadCombinedData(forceRefresh: Bool = false) async {
        if !forceRefresh && self.combinedData != nil { return }

        self.isLoading = true
        self.lastError = nil

        defer {
            self.isLoading = false
        }

        // Load all providers in parallel
        await withTaskGroup(of: Void.self) { group in
            for provider in UsageHistoryProvider.allCases {
                group.addTask {
                    await self.loadData(for: provider, forceRefresh: forceRefresh)
                }
            }
        }

        // Combine all loaded data
        var allDaily: [CostUsageDailyReport.Entry] = []
        var allModels: Set<String> = []

        if let data = self.claudeData {
            allDaily.append(contentsOf: data.daily)
            allModels.formUnion(data.allModels)
        }
        if let data = self.codexData {
            allDaily.append(contentsOf: data.daily)
            allModels.formUnion(data.allModels)
        }
        if let data = self.vertexaiData {
            allDaily.append(contentsOf: data.daily)
            allModels.formUnion(data.allModels)
        }
        if let data = self.ampData {
            allDaily.append(contentsOf: data.daily)
            allModels.formUnion(data.allModels)
        }

        // Aggregate entries by date (combine same-date entries from different providers)
        let aggregated = Self.aggregateDailyByDate(allDaily)

        self.combinedData = ProviderHistoryData(
            provider: .claude, // Placeholder, not used for combined
            daily: aggregated,
            allModels: Array(allModels).sorted(),
            loadedAt: Date())
    }

    /// Aggregate daily entries by date, summing tokens and costs.
    private static func aggregateDailyByDate(_ entries: [CostUsageDailyReport.Entry]) -> [CostUsageDailyReport.Entry] {
        var byDate: [String: CostUsageDailyReport.Entry] = [:]

        for entry in entries {
            if var existing = byDate[entry.date] {
                // Sum tokens
                let newInput = (existing.inputTokens ?? 0) + (entry.inputTokens ?? 0)
                let newOutput = (existing.outputTokens ?? 0) + (entry.outputTokens ?? 0)
                let newCacheRead = (existing.cacheReadTokens ?? 0) + (entry.cacheReadTokens ?? 0)
                let newCacheCreation = (existing.cacheCreationTokens ?? 0) + (entry.cacheCreationTokens ?? 0)
                let newTotal = (existing.totalTokens ?? 0) + (entry.totalTokens ?? 0)

                // Sum cost
                var newCost: Double? = nil
                if existing.costUSD != nil || entry.costUSD != nil {
                    newCost = (existing.costUSD ?? 0) + (entry.costUSD ?? 0)
                }

                // Merge models
                var mergedModels = Set(existing.modelsUsed ?? [])
                mergedModels.formUnion(entry.modelsUsed ?? [])

                // Merge model breakdowns
                var mergedBreakdowns = existing.modelBreakdowns ?? []
                if let entryBreakdowns = entry.modelBreakdowns {
                    mergedBreakdowns.append(contentsOf: entryBreakdowns)
                }

                existing = CostUsageDailyReport.Entry(
                    date: entry.date,
                    inputTokens: newInput > 0 ? newInput : nil,
                    outputTokens: newOutput > 0 ? newOutput : nil,
                    cacheReadTokens: newCacheRead > 0 ? newCacheRead : nil,
                    cacheCreationTokens: newCacheCreation > 0 ? newCacheCreation : nil,
                    totalTokens: newTotal > 0 ? newTotal : nil,
                    costUSD: newCost,
                    modelsUsed: mergedModels.isEmpty ? nil : Array(mergedModels).sorted(),
                    modelBreakdowns: mergedBreakdowns.isEmpty ? nil : mergedBreakdowns)
                byDate[entry.date] = existing
            } else {
                byDate[entry.date] = entry
            }
        }

        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Combined data report aggregated by current time period.
    var combinedAggregatedReport: CostUsageAggregatedReport? {
        guard let data = self.combinedData else { return nil }

        let filtered: [CostUsageDailyReport.Entry]
        if self.selectedModels.isEmpty {
            filtered = data.daily
        } else {
            filtered = CostUsageAggregator.filterByModels(data.daily, models: self.selectedModels)
        }

        return CostUsageAggregator.aggregate(daily: filtered, by: self.selectedPeriod)
    }

    /// Combined available models across all providers.
    var combinedAvailableModels: [String] {
        guard let data = self.combinedData else { return [] }
        return data.allModels
    }

    /// Combined model streaks.
    var combinedModelStreaks: [ModelStreak] {
        guard let data = self.combinedData else { return [] }
        return CostUsageAggregator.calculateStreaks(data.daily)
    }

    // MARK: - Private data fetching

    private func fetchAllTimeData(for provider: UsageHistoryProvider) async throws -> ProviderHistoryData {
        // Run scanner on background thread
        let daily = await Task.detached(priority: .userInitiated) {
            var options = CostUsageScanner.Options()
            options.allTime = true
            options.refreshMinIntervalSeconds = 0

            let report = CostUsageScanner.loadDailyReport(
                provider: provider.usageProvider,
                since: Date(),
                until: Date(),
                now: Date(),
                options: options)

            return report.data
        }.value

        let allModels = CostUsageAggregator.extractAllModels(daily)

        return ProviderHistoryData(
            provider: provider,
            daily: daily,
            allModels: allModels,
            loadedAt: Date())
    }
}

/// Cached historical data for a single provider.
struct ProviderHistoryData: Sendable {
    let provider: UsageHistoryProvider
    let daily: [CostUsageDailyReport.Entry]
    let allModels: [String]
    let loadedAt: Date
}
