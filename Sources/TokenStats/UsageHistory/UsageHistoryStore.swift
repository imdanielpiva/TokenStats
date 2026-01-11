import TokenStatsCore
import Foundation
import Observation

/// Providers that support historical usage data.
enum UsageHistoryProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case vertexai

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .vertexai: "VertexAI"
        }
    }

    var usageProvider: UsageProvider {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .vertexai: .vertexai
        }
    }
}

/// Observable store for Usage History window state.
@Observable
@MainActor
final class UsageHistoryStore {
    // MARK: - Selection state

    var selectedProvider: UsageHistoryProvider = .claude
    var selectedPeriod: CostUsageTimePeriod = .month
    var selectedModels: Set<String> = []

    // MARK: - Data state

    private(set) var isLoading: Bool = false
    private(set) var loadingProvider: UsageHistoryProvider?
    private(set) var lastError: String?

    // Per-provider data cache
    private(set) var claudeData: ProviderHistoryData?
    private(set) var codexData: ProviderHistoryData?
    private(set) var vertexaiData: ProviderHistoryData?

    // MARK: - Budget state

    @ObservationIgnored private let userDefaults = UserDefaults.standard

    /// Get or set monthly budget for a provider.
    func monthlyBudget(for provider: UsageHistoryProvider) -> Double? {
        let key = "monthlyBudget_\(provider.rawValue)"
        let value = self.userDefaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    func setMonthlyBudget(_ budget: Double?, for provider: UsageHistoryProvider) {
        let key = "monthlyBudget_\(provider.rawValue)"
        if let budget, budget > 0 {
            self.userDefaults.set(budget, forKey: key)
        } else {
            self.userDefaults.removeObject(forKey: key)
        }
    }

    /// Binding for current provider's budget.
    var currentProviderBudget: Double? {
        get { self.monthlyBudget(for: self.selectedProvider) }
        set { self.setMonthlyBudget(newValue, for: self.selectedProvider) }
    }

    // MARK: - Computed accessors

    var currentProviderData: ProviderHistoryData? {
        switch self.selectedProvider {
        case .claude: self.claudeData
        case .codex: self.codexData
        case .vertexai: self.vertexaiData
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
