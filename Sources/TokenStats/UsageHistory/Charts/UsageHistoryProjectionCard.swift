import TokenStatsCore
import SwiftUI

/// Shows projected monthly spend card.
struct UsageHistoryProjectionCard: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    private var currentMonthData: MonthProjection? {
        Self.calculateProjection(entries: self.entries)
    }

    var body: some View {
        if let projection = self.currentMonthData {
            self.projectionCard(projection)
        }
    }

    // MARK: - Projection Card

    private func projectionCard(_ projection: MonthProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Projected Monthly Spend", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(projection.monthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 16) {
                // Current spend
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(UsageFormatter.usdString(projection.currentSpend))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                // Projected spend
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(UsageFormatter.usdString(projection.projectedSpend))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Pace indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Daily Avg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(UsageFormatter.usdString(projection.dailyAverage))
                        .font(.callout)
                        .fontWeight(.medium)
                }
            }

            // Progress through month
            self.monthProgressBar(projection)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func monthProgressBar(_ projection: MonthProjection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    // Days elapsed
                    RoundedRectangle(cornerRadius: 4)
                        .fill(self.providerColor.opacity(0.6))
                        .frame(width: geo.size.width * projection.monthProgress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Day \(projection.daysElapsed) of \(projection.daysInMonth)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(projection.monthProgress * 100))% through month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerColor: Color {
        switch self.provider {
        case .claude:
            Color(red: 0.84, green: 0.45, blue: 0.28)
        case .codex:
            Color(red: 0.10, green: 0.65, blue: 0.45)
        case .vertexai:
            Color(red: 0.25, green: 0.52, blue: 0.96)
        case .amp:
            Color(red: 0.95, green: 0.31, blue: 0.25)
        }
    }

    // MARK: - Projection Calculation

    struct MonthProjection {
        let monthLabel: String
        let currentSpend: Double
        let projectedSpend: Double
        let dailyAverage: Double
        let daysElapsed: Int
        let daysInMonth: Int
        let monthProgress: Double
    }

    static func calculateProjection(entries: [CostUsageAggregatedEntry]) -> MonthProjection? {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        // Filter entries for current month
        let currentMonthEntries = entries.filter { entry in
            let month = calendar.component(.month, from: entry.periodStart)
            let year = calendar.component(.year, from: entry.periodStart)
            return month == currentMonth && year == currentYear
        }

        guard !currentMonthEntries.isEmpty else { return nil }

        // Calculate current spend
        let currentSpend = currentMonthEntries.compactMap(\.costUSD).reduce(0, +)

        // Calculate days in month and days elapsed
        guard let monthRange = calendar.range(of: .day, in: .month, for: now) else { return nil }
        let daysInMonth = monthRange.count
        let dayOfMonth = calendar.component(.day, from: now)

        // Daily average based on actual usage days, not calendar days
        let usageDays = currentMonthEntries.count
        let dailyAverage = usageDays > 0 ? currentSpend / Double(usageDays) : 0

        // Project to month end (remaining days * daily average)
        let remainingDays = daysInMonth - dayOfMonth
        let projectedSpend = currentSpend + (dailyAverage * Double(remainingDays))

        // Month progress
        let monthProgress = Double(dayOfMonth) / Double(daysInMonth)

        // Month label
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let monthLabel = formatter.string(from: now)

        return MonthProjection(
            monthLabel: monthLabel,
            currentSpend: currentSpend,
            projectedSpend: projectedSpend,
            dailyAverage: dailyAverage,
            daysElapsed: dayOfMonth,
            daysInMonth: daysInMonth,
            monthProgress: monthProgress)
    }
}

#Preview {
    UsageHistoryProjectionCard(
        entries: [
            CostUsageAggregatedEntry(
                id: "2025-01-01",
                periodLabel: "Jan 1",
                periodStart: Date().addingTimeInterval(-86400 * 10),
                periodEnd: Date().addingTimeInterval(-86400 * 9),
                inputTokens: 100_000,
                outputTokens: 50_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 150_000,
                costUSD: 15.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-01-05",
                periodLabel: "Jan 5",
                periodStart: Date().addingTimeInterval(-86400 * 5),
                periodEnd: Date().addingTimeInterval(-86400 * 4),
                inputTokens: 200_000,
                outputTokens: 100_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 300_000,
                costUSD: 25.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-01-10",
                periodLabel: "Jan 10",
                periodStart: Date(),
                periodEnd: Date().addingTimeInterval(86400),
                inputTokens: 150_000,
                outputTokens: 75_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 225_000,
                costUSD: 18.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
        ],
        provider: .claude)
        .padding()
        .frame(width: 400)
}
