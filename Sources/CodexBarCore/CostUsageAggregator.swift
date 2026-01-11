import Foundation

/// Aggregation time periods for usage history charts.
public enum CostUsageTimePeriod: String, Sendable, CaseIterable {
    case day
    case week
    case month
    case halfYear
    case year

    public var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .halfYear: "6-Month"
        case .year: "Year"
        }
    }
}

/// Aggregated usage entry for a time period.
public struct CostUsageAggregatedEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let periodLabel: String
    public let periodStart: Date
    public let periodEnd: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheCreationTokens: Int
    public let totalTokens: Int
    public let costUSD: Double?
    public let modelsUsed: [String]
    public let modelBreakdowns: [CostUsageDailyReport.ModelBreakdown]

    public init(
        id: String,
        periodLabel: String,
        periodStart: Date,
        periodEnd: Date,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        totalTokens: Int,
        costUSD: Double?,
        modelsUsed: [String],
        modelBreakdowns: [CostUsageDailyReport.ModelBreakdown])
    {
        self.id = id
        self.periodLabel = periodLabel
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.modelsUsed = modelsUsed
        self.modelBreakdowns = modelBreakdowns
    }
}

/// Aggregated usage report with summary.
public struct CostUsageAggregatedReport: Sendable, Equatable {
    public let period: CostUsageTimePeriod
    public let entries: [CostUsageAggregatedEntry]
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCacheReadTokens: Int
    public let totalCacheCreationTokens: Int
    public let totalTokens: Int
    public let totalCostUSD: Double?
    public let allModels: [String]

    public init(
        period: CostUsageTimePeriod,
        entries: [CostUsageAggregatedEntry],
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCacheReadTokens: Int,
        totalCacheCreationTokens: Int,
        totalTokens: Int,
        totalCostUSD: Double?,
        allModels: [String])
    {
        self.period = period
        self.entries = entries
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCacheReadTokens = totalCacheReadTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.allModels = allModels
    }
}

public struct ModelStreak: Sendable, Equatable, Identifiable {
    public let modelName: String
    public let currentStreak: Int
    public let longestStreak: Int
    public let lastActiveDate: String?

    public var id: String { self.modelName }

    public init(modelName: String, currentStreak: Int, longestStreak: Int, lastActiveDate: String?) {
        self.modelName = modelName
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
    }
}

public enum CostUsageAggregator {
    // MARK: - Main aggregation function

    /// Aggregate daily entries by the specified time period.
    public static func aggregate(
        daily: [CostUsageDailyReport.Entry],
        by period: CostUsageTimePeriod) -> CostUsageAggregatedReport
    {
        switch period {
        case .day:
            return self.aggregateByDay(daily)
        case .week:
            return self.aggregateByWeek(daily)
        case .month:
            return self.aggregateByMonth(daily)
        case .halfYear:
            return self.aggregateByHalfYear(daily)
        case .year:
            return self.aggregateByYear(daily)
        }
    }

    // MARK: - Streak calculation

    public static func calculateStreaks(_ daily: [CostUsageDailyReport.Entry]) -> [ModelStreak] {
        var modelDays: [String: Set<String>] = [:]

        for entry in daily {
            let models: [String]
            if let breakdowns = entry.modelBreakdowns {
                models = breakdowns.map(\.modelName)
            } else if let used = entry.modelsUsed {
                models = used
            } else {
                continue
            }

            for model in models {
                modelDays[model, default: []].insert(entry.date)
            }
        }

        let calendar = Calendar.current
        let todayKey = Self.todayKey()

        var streaks: [ModelStreak] = []

        for (model, days) in modelDays {
            let sortedDays = days.sorted()
            guard !sortedDays.isEmpty else { continue }

            var currentStreak = 0
            var longestStreak = 0
            var tempStreak = 1

            for i in 1..<sortedDays.count {
                if Self.areConsecutiveDays(sortedDays[i - 1], sortedDays[i], calendar: calendar) {
                    tempStreak += 1
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                }
            }
            longestStreak = max(longestStreak, tempStreak)

            let lastDay = sortedDays.last!
            if lastDay == todayKey {
                currentStreak = 1
                var idx = sortedDays.count - 2
                while idx >= 0 {
                    if Self.areConsecutiveDays(sortedDays[idx], sortedDays[idx + 1], calendar: calendar) {
                        currentStreak += 1
                        idx -= 1
                    } else {
                        break
                    }
                }
            } else if let yesterday = Self.yesterdayKey(), lastDay == yesterday {
                currentStreak = 1
                var idx = sortedDays.count - 2
                while idx >= 0 {
                    if Self.areConsecutiveDays(sortedDays[idx], sortedDays[idx + 1], calendar: calendar) {
                        currentStreak += 1
                        idx -= 1
                    } else {
                        break
                    }
                }
            }

            streaks.append(ModelStreak(
                modelName: model,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                lastActiveDate: lastDay))
        }

        return streaks.sorted { $0.currentStreak > $1.currentStreak }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private static func yesterdayKey() -> String? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: yesterday)
    }

    private static func areConsecutiveDays(_ day1: String, _ day2: String, calendar: Calendar) -> Bool {
        guard let date1 = Self.parseDate(day1),
              let date2 = Self.parseDate(day2) else { return false }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date1) else { return false }
        return calendar.isDate(nextDay, inSameDayAs: date2)
    }

    // MARK: - Model filtering

    /// Filter daily entries to only include specified models.
    public static func filterByModels(
        _ daily: [CostUsageDailyReport.Entry],
        models: Set<String>) -> [CostUsageDailyReport.Entry]
    {
        guard !models.isEmpty else { return daily }

        return daily.compactMap { entry in
            // Filter model breakdowns
            guard let breakdowns = entry.modelBreakdowns else {
                // If no breakdowns, check modelsUsed
                if let used = entry.modelsUsed, !used.isEmpty {
                    let matching = used.filter { models.contains($0) }
                    if matching.isEmpty { return nil }
                }
                return entry
            }

            let filtered = breakdowns.filter { models.contains($0.modelName) }
            if filtered.isEmpty { return nil }

            // Recalculate totals from filtered breakdowns
            let newCost = filtered.compactMap(\.costUSD).reduce(0, +)

            return CostUsageDailyReport.Entry(
                date: entry.date,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheReadTokens: entry.cacheReadTokens,
                cacheCreationTokens: entry.cacheCreationTokens,
                totalTokens: entry.totalTokens,
                costUSD: newCost > 0 ? newCost : entry.costUSD,
                modelsUsed: filtered.map(\.modelName),
                modelBreakdowns: filtered)
        }
    }

    /// Extract all unique model names from daily entries.
    public static func extractAllModels(_ daily: [CostUsageDailyReport.Entry]) -> [String] {
        var models: Set<String> = []
        for entry in daily {
            if let breakdowns = entry.modelBreakdowns {
                for breakdown in breakdowns {
                    models.insert(breakdown.modelName)
                }
            } else if let used = entry.modelsUsed {
                for model in used {
                    models.insert(model)
                }
            }
        }
        return models.sorted()
    }

    // MARK: - Day aggregation (passthrough with conversion)

    private static func aggregateByDay(_ daily: [CostUsageDailyReport.Entry]) -> CostUsageAggregatedReport {
        let calendar = Calendar.current
        var entries: [CostUsageAggregatedEntry] = []
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreate = 0
        var totalTokens = 0
        var totalCost: Double = 0
        var costSeen = false
        var allModels: Set<String> = []

        for entry in daily.sorted(by: { $0.date < $1.date }) {
            guard let date = self.parseDate(entry.date) else { continue }

            let input = entry.inputTokens ?? 0
            let output = entry.outputTokens ?? 0
            let cacheRead = entry.cacheReadTokens ?? 0
            let cacheCreate = entry.cacheCreationTokens ?? 0
            let tokens = entry.totalTokens ?? (input + output + cacheRead + cacheCreate)

            totalInput += input
            totalOutput += output
            totalCacheRead += cacheRead
            totalCacheCreate += cacheCreate
            totalTokens += tokens

            if let cost = entry.costUSD {
                totalCost += cost
                costSeen = true
            }

            let models = entry.modelsUsed ?? entry.modelBreakdowns?.map(\.modelName) ?? []
            for m in models { allModels.insert(m) }

            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let label = self.formatDayLabel(date)

            entries.append(CostUsageAggregatedEntry(
                id: entry.date,
                periodLabel: label,
                periodStart: date,
                periodEnd: dayEnd,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheCreate,
                totalTokens: tokens,
                costUSD: entry.costUSD,
                modelsUsed: models,
                modelBreakdowns: entry.modelBreakdowns ?? []))
        }

        return CostUsageAggregatedReport(
            period: .day,
            entries: entries,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheCreationTokens: totalCacheCreate,
            totalTokens: totalTokens,
            totalCostUSD: costSeen ? totalCost : nil,
            allModels: allModels.sorted())
    }

    // MARK: - Week aggregation (ISO week)

    private static func aggregateByWeek(_ daily: [CostUsageDailyReport.Entry]) -> CostUsageAggregatedReport {
        self.aggregateByPeriod(daily, period: .week) { date, calendar in
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let year = comps.yearForWeekOfYear ?? 1970
            let week = comps.weekOfYear ?? 1
            return String(format: "%04d-W%02d", year, week)
        } periodBounds: { key, calendar in
            let parts = key.split(separator: "-W")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let week = Int(parts[1])
            else { return (Date.distantPast, Date.distantFuture) }

            var comps = DateComponents()
            comps.yearForWeekOfYear = year
            comps.weekOfYear = week
            comps.weekday = calendar.firstWeekday
            let start = calendar.date(from: comps) ?? Date.distantPast
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? Date.distantFuture
            return (start, end)
        } formatLabel: { key, _ in
            // Convert "2025-W03" to "Jan 13" (first day of week)
            let parts = key.split(separator: "-W")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let week = Int(parts[1])
            else { return key }

            var comps = DateComponents()
            comps.yearForWeekOfYear = year
            comps.weekOfYear = week
            comps.weekday = Calendar.current.firstWeekday
            guard let date = Calendar.current.date(from: comps) else { return key }
            return self.formatWeekLabel(date)
        }
    }

    // MARK: - Month aggregation

    private static func aggregateByMonth(_ daily: [CostUsageDailyReport.Entry]) -> CostUsageAggregatedReport {
        self.aggregateByPeriod(daily, period: .month) { date, calendar in
            let comps = calendar.dateComponents([.year, .month], from: date)
            let year = comps.year ?? 1970
            let month = comps.month ?? 1
            return String(format: "%04d-%02d", year, month)
        } periodBounds: { key, calendar in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1])
            else { return (Date.distantPast, Date.distantFuture) }

            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            let start = calendar.date(from: comps) ?? Date.distantPast
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? Date.distantFuture
            return (start, end)
        } formatLabel: { key, _ in
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1])
            else { return key }

            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            guard let date = Calendar.current.date(from: comps) else { return key }
            return self.formatMonthLabel(date)
        }
    }

    // MARK: - Half-year aggregation

    private static func aggregateByHalfYear(_ daily: [CostUsageDailyReport.Entry]) -> CostUsageAggregatedReport {
        self.aggregateByPeriod(daily, period: .halfYear) { date, calendar in
            let comps = calendar.dateComponents([.year, .month], from: date)
            let year = comps.year ?? 1970
            let month = comps.month ?? 1
            let half = month <= 6 ? 1 : 2
            return String(format: "%04d-H%d", year, half)
        } periodBounds: { key, calendar in
            let parts = key.split(separator: "-H")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let half = Int(parts[1])
            else { return (Date.distantPast, Date.distantFuture) }

            var comps = DateComponents()
            comps.year = year
            comps.month = half == 1 ? 1 : 7
            comps.day = 1
            let start = calendar.date(from: comps) ?? Date.distantPast
            let end = calendar.date(byAdding: .month, value: 6, to: start) ?? Date.distantFuture
            return (start, end)
        } formatLabel: { key, _ in
            let parts = key.split(separator: "-H")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let half = Int(parts[1])
            else { return key }
            return half == 1 ? "Jan-Jun \(year)" : "Jul-Dec \(year)"
        }
    }

    // MARK: - Year aggregation

    private static func aggregateByYear(_ daily: [CostUsageDailyReport.Entry]) -> CostUsageAggregatedReport {
        self.aggregateByPeriod(daily, period: .year) { date, calendar in
            let comps = calendar.dateComponents([.year], from: date)
            let year = comps.year ?? 1970
            return String(format: "%04d", year)
        } periodBounds: { key, calendar in
            guard let year = Int(key) else { return (Date.distantPast, Date.distantFuture) }

            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            let start = calendar.date(from: comps) ?? Date.distantPast
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? Date.distantFuture
            return (start, end)
        } formatLabel: { key, _ in
            key
        }
    }

    // MARK: - Generic period aggregation

    private static func aggregateByPeriod(
        _ daily: [CostUsageDailyReport.Entry],
        period: CostUsageTimePeriod,
        periodKey: (Date, Calendar) -> String,
        periodBounds: (String, Calendar) -> (start: Date, end: Date),
        formatLabel: (String, Calendar) -> String) -> CostUsageAggregatedReport
    {
        let calendar = Calendar.current

        // Group entries by period key
        var groups: [String: [CostUsageDailyReport.Entry]] = [:]
        for entry in daily {
            guard let date = self.parseDate(entry.date) else { continue }
            let key = periodKey(date, calendar)
            groups[key, default: []].append(entry)
        }

        // Aggregate each group
        var entries: [CostUsageAggregatedEntry] = []
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreate = 0
        var totalTokens = 0
        var totalCost: Double = 0
        var costSeen = false
        var allModels: Set<String> = []

        for key in groups.keys.sorted() {
            guard let group = groups[key] else { continue }
            let bounds = periodBounds(key, calendar)
            let label = formatLabel(key, calendar)

            var input = 0
            var output = 0
            var cacheRead = 0
            var cacheCreate = 0
            var tokens = 0
            var cost: Double = 0
            var hasCost = false
            var models: Set<String> = []
            var breakdownMap: [String: Double] = [:]

            for entry in group {
                input += entry.inputTokens ?? 0
                output += entry.outputTokens ?? 0
                cacheRead += entry.cacheReadTokens ?? 0
                cacheCreate += entry.cacheCreationTokens ?? 0
                tokens += entry.totalTokens ?? 0

                if let c = entry.costUSD {
                    cost += c
                    hasCost = true
                }

                if let breakdowns = entry.modelBreakdowns {
                    for bd in breakdowns {
                        models.insert(bd.modelName)
                        allModels.insert(bd.modelName)
                        if let c = bd.costUSD {
                            breakdownMap[bd.modelName, default: 0] += c
                        }
                    }
                } else if let used = entry.modelsUsed {
                    for m in used {
                        models.insert(m)
                        allModels.insert(m)
                    }
                }
            }

            totalInput += input
            totalOutput += output
            totalCacheRead += cacheRead
            totalCacheCreate += cacheCreate
            totalTokens += tokens
            if hasCost {
                totalCost += cost
                costSeen = true
            }

            let breakdowns = breakdownMap.map { CostUsageDailyReport.ModelBreakdown(modelName: $0.key, costUSD: $0.value) }
                .sorted { ($0.costUSD ?? 0) > ($1.costUSD ?? 0) }

            entries.append(CostUsageAggregatedEntry(
                id: key,
                periodLabel: label,
                periodStart: bounds.start,
                periodEnd: bounds.end,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheCreate,
                totalTokens: tokens,
                costUSD: hasCost ? cost : nil,
                modelsUsed: models.sorted(),
                modelBreakdowns: breakdowns))
        }

        return CostUsageAggregatedReport(
            period: period,
            entries: entries,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheCreationTokens: totalCacheCreate,
            totalTokens: totalTokens,
            totalCostUSD: costSeen ? totalCost : nil,
            allModels: allModels.sorted())
    }

    // MARK: - Date parsing and formatting

    private static func parseDate(_ dateString: String) -> Date? {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return comps.date
    }

    private static func formatDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func formatWeekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func formatMonthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}
