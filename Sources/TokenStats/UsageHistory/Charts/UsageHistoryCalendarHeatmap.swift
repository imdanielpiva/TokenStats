import TokenStatsCore
import SwiftUI

/// GitHub-style calendar heatmap showing daily activity intensity.
struct UsageHistoryCalendarHeatmap: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    @State private var hoveredDate: Date?

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    private var entriesByDate: [String: CostUsageAggregatedEntry] {
        Dictionary(uniqueKeysWithValues: self.entries.map { (self.dateKey($0.periodStart), $0) })
    }

    private var maxTokens: Int {
        self.entries.map(\.totalTokens).max() ?? 1
    }

    private var weeks: [[Date?]] {
        let calendar = Calendar.current
        let today = Date()

        // Go back ~3 months (13 weeks)
        guard let startDate = calendar.date(byAdding: .weekOfYear, value: -12, to: today) else { return [] }

        // Align to start of week
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)) ?? startDate

        var weeks: [[Date?]] = []
        var currentDate = weekStart

        while currentDate <= today {
            var week: [Date?] = []
            for _ in 0..<7 {
                if currentDate <= today {
                    week.append(currentDate)
                } else {
                    week.append(nil)
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            weeks.append(week)
        }

        return weeks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Month labels
            self.monthLabels

            HStack(alignment: .top, spacing: 4) {
                // Weekday labels
                self.weekdayLabels

                // Calendar grid
                HStack(spacing: self.cellSpacing) {
                    ForEach(Array(self.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: self.cellSpacing) {
                            ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, date in
                                self.dayCell(date: date, dayOfWeek: dayIndex)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 8) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 2) {
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(self.colorForLevel(level))
                            .frame(width: self.cellSize, height: self.cellSize)
                    }
                }

                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                // Hovered day info
                if let date = self.hoveredDate {
                    self.hoveredDateInfo(date)
                }
            }
        }
    }

    private var monthLabels: some View {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        // Calculate month labels with positions
        var monthPositions: [(month: String, offset: Int)] = []
        var lastMonth = -1

        for (weekIndex, week) in self.weeks.enumerated() {
            if let firstDay = week.first(where: { $0 != nil }) ?? nil {
                let month = calendar.component(.month, from: firstDay)
                if month != lastMonth {
                    monthPositions.append((formatter.string(from: firstDay), weekIndex))
                    lastMonth = month
                }
            }
        }

        return HStack(spacing: 0) {
            // Offset for weekday labels
            Text("")
                .frame(width: 24)

            ZStack(alignment: .leading) {
                ForEach(Array(monthPositions.enumerated()), id: \.offset) { _, item in
                    Text(item.month)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .offset(x: CGFloat(item.offset) * (self.cellSize + self.cellSpacing))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weekdayLabels: some View {
        let days = ["", "M", "", "W", "", "F", ""]
        return VStack(spacing: self.cellSpacing) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: self.cellSize)
            }
        }
    }

    @ViewBuilder
    private func dayCell(date: Date?, dayOfWeek: Int) -> some View {
        if let date {
            let key = self.dateKey(date)
            let entry = self.entriesByDate[key]
            let level = self.intensityLevel(for: entry)

            RoundedRectangle(cornerRadius: 2)
                .fill(self.colorForLevel(level))
                .frame(width: self.cellSize, height: self.cellSize)
                .overlay {
                    if self.hoveredDate == date {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.primary.opacity(0.5), lineWidth: 1)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        self.hoveredDate = date
                    case .ended:
                        if self.hoveredDate == date {
                            self.hoveredDate = nil
                        }
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.clear)
                .frame(width: self.cellSize, height: self.cellSize)
        }
    }

    private func hoveredDateInfo(_ date: Date) -> some View {
        let key = self.dateKey(date)
        let entry = self.entriesByDate[key]
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        return HStack(spacing: 8) {
            Text(formatter.string(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let entry {
                Text("\(UsageFormatter.tokenCountString(entry.totalTokens)) tokens")
                    .font(.caption)
                    .fontWeight(.medium)

                if let cost = entry.costUSD, cost > 0 {
                    Text(UsageFormatter.usdString(cost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No activity")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func intensityLevel(for entry: CostUsageAggregatedEntry?) -> Int {
        guard let entry, entry.totalTokens > 0 else { return 0 }

        let ratio = Double(entry.totalTokens) / Double(max(self.maxTokens, 1))

        if ratio > 0.75 { return 4 }
        if ratio > 0.50 { return 3 }
        if ratio > 0.25 { return 2 }
        return 1
    }

    private func colorForLevel(_ level: Int) -> Color {
        let baseColor: Color = switch self.provider {
        case .claude:
            Color(red: 0.84, green: 0.45, blue: 0.28)
        case .codex:
            Color(red: 0.10, green: 0.65, blue: 0.45)
        case .vertexai:
            Color(red: 0.25, green: 0.52, blue: 0.96)
        case .amp:
            Color(red: 0.95, green: 0.31, blue: 0.25)
        }

        switch level {
        case 0:
            return Color(nsColor: .separatorColor).opacity(0.3)
        case 1:
            return baseColor.opacity(0.3)
        case 2:
            return baseColor.opacity(0.5)
        case 3:
            return baseColor.opacity(0.7)
        case 4:
            return baseColor.opacity(1.0)
        default:
            return baseColor
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()

    // Generate some sample data for the last few weeks
    var entries: [CostUsageAggregatedEntry] = []
    for daysAgo in stride(from: 0, to: 60, by: 1) {
        guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
        // Random activity
        if Bool.random() {
            let tokens = Int.random(in: 10_000...500_000)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            entries.append(CostUsageAggregatedEntry(
                id: formatter.string(from: date),
                periodLabel: "",
                periodStart: date,
                periodEnd: date,
                inputTokens: tokens / 2,
                outputTokens: tokens / 2,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: tokens,
                costUSD: Double(tokens) / 1000 * 0.015,
                modelsUsed: [],
                modelBreakdowns: []))
        }
    }

    return UsageHistoryCalendarHeatmap(entries: entries, provider: .claude)
        .padding()
}
