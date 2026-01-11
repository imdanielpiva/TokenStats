import Charts
import TokenStatsCore
import SwiftUI

/// Bar chart showing usage aggregated by day of week.
struct UsageHistoryWeekdayChart: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    @State private var selectedWeekday: Int?

    private struct WeekdayData: Identifiable {
        let weekday: Int // 1 = Sunday, 7 = Saturday
        let name: String
        let shortName: String
        let totalTokens: Int
        let totalCost: Double
        let dayCount: Int

        var id: Int { self.weekday }
        var averageTokens: Int { self.dayCount > 0 ? self.totalTokens / self.dayCount : 0 }
    }

    private var weekdayData: [WeekdayData] {
        let calendar = Calendar.current

        // Group entries by weekday
        var weekdayTotals: [Int: (tokens: Int, cost: Double, count: Int)] = [:]

        for entry in self.entries {
            let weekday = calendar.component(.weekday, from: entry.periodStart)
            let existing = weekdayTotals[weekday, default: (tokens: 0, cost: 0, count: 0)]
            weekdayTotals[weekday] = (
                tokens: existing.tokens + entry.totalTokens,
                cost: existing.cost + (entry.costUSD ?? 0),
                count: existing.count + 1
            )
        }

        // Create data for all weekdays (starting from Monday)
        let weekdayOrder = [2, 3, 4, 5, 6, 7, 1] // Mon-Sun
        let weekdayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekdayFullNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

        return weekdayOrder.map { weekday in
            let data = weekdayTotals[weekday, default: (tokens: 0, cost: 0, count: 0)]
            return WeekdayData(
                weekday: weekday,
                name: weekdayFullNames[weekday],
                shortName: weekdayNames[weekday],
                totalTokens: data.tokens,
                totalCost: data.cost,
                dayCount: data.count)
        }
    }

    private var maxTokens: Int {
        self.weekdayData.map(\.totalTokens).max() ?? 0
    }

    var body: some View {
        if self.entries.isEmpty {
            self.emptyView
        } else {
            self.chartView
        }
    }

    private var emptyView: some View {
        Text("No data for weekday analysis")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(self.weekdayData) { day in
                BarMark(
                    x: .value("Day", day.shortName),
                    y: .value("Tokens", day.totalTokens))
                    .foregroundStyle(self.barColor(for: day).opacity(self.selectedWeekday == day.weekday ? 1.0 : 0.8))
                    .annotation(position: .top, alignment: .center) {
                        if day.totalTokens == self.maxTokens && self.maxTokens > 0 {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(self.formatTokenCount(tokens))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                self.updateSelection(at: location, proxy: proxy, geo: geo)
                            case .ended:
                                self.selectedWeekday = nil
                            }
                        }
                }
            }

            // Detail text
            self.detailText
                .frame(height: 32)
        }
    }

    @ViewBuilder
    private var detailText: some View {
        if let weekday = self.selectedWeekday,
           let day = self.weekdayData.first(where: { $0.weekday == weekday })
        {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day.name): \(UsageFormatter.tokenCountString(day.totalTokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("\(day.dayCount) \(day.dayCount == 1 ? "day" : "days") tracked")
                    if day.dayCount > 0 {
                        Text("Avg: \(UsageFormatter.tokenCountString(day.averageTokens))/day")
                    }
                    if day.totalCost > 0 {
                        Text("Cost: \(UsageFormatter.usdString(day.totalCost))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        } else {
            Text("Hover a bar for weekday details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func barColor(for day: WeekdayData) -> Color {
        // Weekend vs weekday distinction
        let isWeekend = day.weekday == 1 || day.weekday == 7

        switch self.provider {
        case .claude:
            return isWeekend
                ? Color(red: 0.70, green: 0.35, blue: 0.18) // Darker for weekends
                : Color(red: 0.84, green: 0.45, blue: 0.28)
        case .codex:
            return isWeekend
                ? Color(red: 0.05, green: 0.55, blue: 0.35)
                : Color(red: 0.10, green: 0.65, blue: 0.45)
        case .vertexai:
            return isWeekend
                ? Color(red: 0.15, green: 0.42, blue: 0.86)
                : Color(red: 0.25, green: 0.52, blue: 0.96)
        case .amp:
            return isWeekend
                ? Color(red: 0.85, green: 0.20, blue: 0.15) // Darker Amp red for weekends
                : Color(red: 0.95, green: 0.31, blue: 0.25)
        }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        guard frame.contains(location) else {
            self.selectedWeekday = nil
            return
        }

        let xInPlot = location.x - frame.origin.x
        guard let label: String = proxy.value(atX: xInPlot) else { return }

        if let day = self.weekdayData.first(where: { $0.shortName == label }) {
            self.selectedWeekday = day.weekday
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    UsageHistoryWeekdayChart(
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
                modelsUsed: [],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-01-07",
                periodLabel: "Jan 7",
                periodStart: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 7))!,
                periodEnd: Date(),
                inputTokens: 800_000,
                outputTokens: 400_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 1_200_000,
                costUSD: 22.00,
                modelsUsed: [],
                modelBreakdowns: []),
        ],
        provider: .claude)
        .frame(height: 200)
        .padding()
}
