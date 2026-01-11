import TokenStatsCore
import SwiftUI

/// Fun statistics and badges derived from usage data.
struct UsageHistoryFunStats: View {
    let entries: [CostUsageAggregatedEntry]
    let report: CostUsageAggregatedReport

    private struct FunStat: Identifiable {
        let id: String
        let icon: String
        let iconColor: Color
        let title: String
        let value: String
        let subtitle: String?
    }

    private var stats: [FunStat] {
        var result: [FunStat] = []

        // Most expensive day
        if let maxCostEntry = self.entries.filter({ $0.costUSD != nil }).max(by: { ($0.costUSD ?? 0) < ($1.costUSD ?? 0) }),
           let cost = maxCostEntry.costUSD, cost > 0
        {
            result.append(FunStat(
                id: "most_expensive",
                icon: "flame.fill",
                iconColor: .orange,
                title: "Biggest Spend",
                value: UsageFormatter.usdString(cost),
                subtitle: maxCostEntry.periodLabel))
        }

        // Most tokens in a day
        if let maxTokenEntry = self.entries.max(by: { $0.totalTokens < $1.totalTokens }),
           maxTokenEntry.totalTokens > 0
        {
            result.append(FunStat(
                id: "most_tokens",
                icon: "bolt.fill",
                iconColor: .yellow,
                title: "Peak Activity",
                value: UsageFormatter.tokenCountString(maxTokenEntry.totalTokens),
                subtitle: maxTokenEntry.periodLabel))
        }

        // Busiest weekday
        if let busiestDay = self.busiestWeekday() {
            result.append(FunStat(
                id: "busiest_weekday",
                icon: "calendar.badge.clock",
                iconColor: .blue,
                title: "Busiest Day",
                value: busiestDay.name,
                subtitle: "\(UsageFormatter.tokenCountString(busiestDay.tokens)) total"))
        }

        // Weekend warrior or weekday worker
        let weekendVsWeekday = self.weekendVsWeekdayRatio()
        if weekendVsWeekday.total > 0 {
            let isWeekendWarrior = weekendVsWeekday.weekendRatio > 0.4
            result.append(FunStat(
                id: "work_style",
                icon: isWeekendWarrior ? "moon.stars.fill" : "sun.max.fill",
                iconColor: isWeekendWarrior ? .purple : .orange,
                title: isWeekendWarrior ? "Weekend Warrior" : "Weekday Worker",
                value: String(format: "%.0f%%", (isWeekendWarrior ? weekendVsWeekday.weekendRatio : weekendVsWeekday.weekdayRatio) * 100),
                subtitle: isWeekendWarrior ? "weekend usage" : "weekday usage"))
        }

        // Output ratio
        let totalInput = self.report.totalInputTokens
        let totalOutput = self.report.totalOutputTokens
        if totalInput + totalOutput > 0 {
            let outputRatio = Double(totalOutput) / Double(totalInput + totalOutput)
            let isOutputHeavy = outputRatio > 0.4
            result.append(FunStat(
                id: "output_ratio",
                icon: isOutputHeavy ? "text.bubble.fill" : "arrow.down.doc.fill",
                iconColor: isOutputHeavy ? .green : .cyan,
                title: isOutputHeavy ? "Chattier AI" : "Prompt Heavy",
                value: String(format: "%.0f%%", outputRatio * 100),
                subtitle: "output tokens"))
        }

        // Favorite model (most used)
        if let favoriteModel = self.favoriteModel() {
            result.append(FunStat(
                id: "favorite_model",
                icon: "heart.fill",
                iconColor: .pink,
                title: "Favorite Model",
                value: UsageFormatter.modelDisplayName(favoriteModel.name),
                subtitle: "\(favoriteModel.dayCount) days used"))
        }

        return result
    }

    var body: some View {
        if self.stats.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12),
            ], spacing: 12) {
                ForEach(self.stats) { stat in
                    self.statCard(stat)
                }
            }
        }
    }

    private func statCard(_ stat: FunStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: stat.icon)
                    .foregroundStyle(stat.iconColor)
                    .font(.caption)

                Text(stat.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(stat.value)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)

            if let subtitle = stat.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Stat calculations

    private func busiestWeekday() -> (name: String, tokens: Int)? {
        let calendar = Calendar.current
        var weekdayTotals: [Int: Int] = [:]

        for entry in self.entries {
            let weekday = calendar.component(.weekday, from: entry.periodStart)
            weekdayTotals[weekday, default: 0] += entry.totalTokens
        }

        guard let (weekday, tokens) = weekdayTotals.max(by: { $0.value < $1.value }),
              tokens > 0
        else { return nil }

        let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return (weekdayNames[weekday], tokens)
    }

    private func weekendVsWeekdayRatio() -> (weekendRatio: Double, weekdayRatio: Double, total: Int) {
        let calendar = Calendar.current
        var weekendTokens = 0
        var weekdayTokens = 0

        for entry in self.entries {
            let weekday = calendar.component(.weekday, from: entry.periodStart)
            if weekday == 1 || weekday == 7 {
                weekendTokens += entry.totalTokens
            } else {
                weekdayTokens += entry.totalTokens
            }
        }

        let total = weekendTokens + weekdayTokens
        guard total > 0 else { return (0, 0, 0) }

        return (
            weekendRatio: Double(weekendTokens) / Double(total),
            weekdayRatio: Double(weekdayTokens) / Double(total),
            total: total
        )
    }

    private func favoriteModel() -> (name: String, dayCount: Int)? {
        var modelDayCounts: [String: Int] = [:]

        for entry in self.entries {
            for model in entry.modelsUsed {
                modelDayCounts[model, default: 0] += 1
            }
        }

        guard let (name, count) = modelDayCounts.max(by: { $0.value < $1.value }),
              count > 0
        else { return nil }

        return (name, count)
    }
}

#Preview {
    UsageHistoryFunStats(
        entries: [
            CostUsageAggregatedEntry(
                id: "2025-01-06",
                periodLabel: "Jan 6",
                periodStart: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 6))!,
                periodEnd: Date(),
                inputTokens: 500_000,
                outputTokens: 200_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 700_000,
                costUSD: 12.50,
                modelsUsed: ["claude-opus-4-5"],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-01-07",
                periodLabel: "Jan 7",
                periodStart: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 7))!,
                periodEnd: Date(),
                inputTokens: 1_800_000,
                outputTokens: 900_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 2_700_000,
                costUSD: 55.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
        ],
        report: CostUsageAggregatedReport(
            period: .day,
            entries: [],
            totalInputTokens: 2_300_000,
            totalOutputTokens: 1_100_000,
            totalCacheReadTokens: 0,
            totalCacheCreationTokens: 0,
            totalTokens: 3_400_000,
            totalCostUSD: 67.50,
            allModels: ["claude-opus-4-5", "claude-sonnet-4-5"]))
        .frame(width: 400)
        .padding()
}
