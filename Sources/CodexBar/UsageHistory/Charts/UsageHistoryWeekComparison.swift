import CodexBarCore
import SwiftUI

/// Week-over-week comparison showing current vs previous week stats.
struct UsageHistoryWeekComparison: View {
    let entries: [CostUsageAggregatedEntry]

    private struct WeekStats {
        let tokens: Int
        let cost: Double
        let activeDays: Int
        let startDate: Date
        let endDate: Date

        var isEmpty: Bool { self.tokens == 0 && self.cost == 0 }
    }

    private var currentWeekStats: WeekStats {
        self.statsForWeek(offset: 0)
    }

    private var previousWeekStats: WeekStats {
        self.statsForWeek(offset: -1)
    }

    private func statsForWeek(offset: Int) -> WeekStats {
        let calendar = Calendar.current
        let today = Date()

        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart),
              let targetWeekEnd = calendar.date(byAdding: .day, value: 7, to: targetWeekStart)
        else {
            return WeekStats(tokens: 0, cost: 0, activeDays: 0, startDate: today, endDate: today)
        }

        var tokens = 0
        var cost: Double = 0
        var activeDays = 0

        for entry in self.entries {
            if entry.periodStart >= targetWeekStart && entry.periodStart < targetWeekEnd {
                tokens += entry.totalTokens
                cost += entry.costUSD ?? 0
                activeDays += 1
            }
        }

        return WeekStats(
            tokens: tokens,
            cost: cost,
            activeDays: activeDays,
            startDate: targetWeekStart,
            endDate: targetWeekEnd)
    }

    private func changePercent(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return current > 0 ? 100 : nil }
        return Double(current - previous) / Double(previous) * 100
    }

    private func changePercent(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return current > 0 ? 100 : nil }
        return (current - previous) / previous * 100
    }

    var body: some View {
        if self.currentWeekStats.isEmpty && self.previousWeekStats.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    // Current week
                    self.weekCard(
                        title: "This Week",
                        stats: self.currentWeekStats,
                        isCurrentWeek: true)

                    // Previous week
                    self.weekCard(
                        title: "Last Week",
                        stats: self.previousWeekStats,
                        isCurrentWeek: false)

                    // Changes
                    if !self.previousWeekStats.isEmpty {
                        self.changesCard
                    }
                }
            }
        }
    }

    private func weekCard(title: String, stats: WeekStats, isCurrentWeek: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isCurrentWeek {
                    Text("(in progress)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(UsageFormatter.tokenCountString(stats.tokens))
                        .font(.callout)
                        .fontWeight(.medium)
                }

                if stats.cost > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(UsageFormatter.usdString(stats.cost))
                            .font(.caption)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(stats.activeDays) active days")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var changesCard: some View {
        let tokenChange = self.changePercent(
            current: self.currentWeekStats.tokens,
            previous: self.previousWeekStats.tokens)
        let costChange = self.changePercent(
            current: self.currentWeekStats.cost,
            previous: self.previousWeekStats.cost)

        VStack(alignment: .leading, spacing: 8) {
            Text("vs Last Week")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                if let change = tokenChange {
                    self.changeRow(label: "Tokens", change: change)
                }

                if let change = costChange {
                    self.changeRow(label: "Cost", change: change)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }

    private func changeRow(label: String, change: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2)
                .foregroundStyle(change >= 0 ? .green : .red)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(String(format: "%+.0f%%", change))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(change >= 0 ? .green : .red)
        }
    }
}

#Preview {
    UsageHistoryWeekComparison(entries: [
        // This week (assuming today is mid-January 2025)
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
            modelsUsed: [],
            modelBreakdowns: []),
        // Last week
        CostUsageAggregatedEntry(
            id: "2025-01-01",
            periodLabel: "Jan 1",
            periodStart: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!,
            periodEnd: Date(),
            inputTokens: 300_000,
            outputTokens: 100_000,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            totalTokens: 400_000,
            costUSD: 8.00,
            modelsUsed: [],
            modelBreakdowns: []),
    ])
    .frame(width: 500)
    .padding()
}
