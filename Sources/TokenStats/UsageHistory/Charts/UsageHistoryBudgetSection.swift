import TokenStatsCore
import SwiftUI

/// Shows projected monthly spend and budget progress bar.
struct UsageHistoryBudgetSection: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider
    @Binding var monthlyBudget: Double?
    @State private var isEditingBudget = false
    @State private var budgetText = ""

    private var currentMonthData: MonthProjection? {
        Self.calculateProjection(entries: self.entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Projected Spend Card
            if let projection = self.currentMonthData {
                self.projectionCard(projection)
            }

            // Budget Progress Bar
            self.budgetSection
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
                        .foregroundStyle(self.projectionColor(projection))
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

    private func projectionColor(_ projection: MonthProjection) -> Color {
        guard let budget = self.monthlyBudget, budget > 0 else {
            return .primary
        }

        let ratio = projection.projectedSpend / budget
        if ratio >= 1.0 {
            return .red
        } else if ratio >= 0.8 {
            return .orange
        } else {
            return .primary
        }
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Monthly Budget", systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if self.isEditingBudget {
                    HStack(spacing: 4) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Budget", text: self.$budgetText)
                            .textFieldStyle(.plain)
                            .frame(width: 80)
                            .onSubmit {
                                self.saveBudget()
                            }
                        Button("Save") {
                            self.saveBudget()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("Cancel") {
                            self.isEditingBudget = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Button {
                        self.budgetText = self.monthlyBudget.map { String(format: "%.0f", $0) } ?? ""
                        self.isEditingBudget = true
                    } label: {
                        if let budget = self.monthlyBudget {
                            Text("\(UsageFormatter.usdString(budget))")
                                .font(.caption)
                        } else {
                            Text("Set Budget")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let budget = self.monthlyBudget, budget > 0, let projection = self.currentMonthData {
                self.budgetProgressBar(budget: budget, spent: projection.currentSpend, projected: projection.projectedSpend)
            } else if self.monthlyBudget == nil {
                Text("Set a monthly budget to track spending against your limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func budgetProgressBar(budget: Double, spent: Double, projected: Double) -> some View {
        let spentRatio = min(spent / budget, 1.0)
        let projectedRatio = min(projected / budget, 1.5)
        let isOverBudget = spent >= budget
        let willExceedBudget = projected >= budget

        return VStack(alignment: .leading, spacing: 8) {
            // Main progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))

                    // Projected indicator (dashed line or subtle fill)
                    if projectedRatio > spentRatio && projectedRatio <= 1.0 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(self.budgetColor(ratio: projectedRatio).opacity(0.2))
                            .frame(width: geo.size.width * projectedRatio)
                    }

                    // Current spend
                    RoundedRectangle(cornerRadius: 6)
                        .fill(self.budgetColor(ratio: spentRatio))
                        .frame(width: geo.size.width * spentRatio)

                    // Budget line at 100%
                    if projectedRatio > 1.0 || spentRatio < 1.0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 2)
                            .offset(x: geo.size.width - 1)
                    }
                }
            }
            .frame(height: 12)

            // Labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent: \(UsageFormatter.usdString(spent))")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(Int(spentRatio * 100))% of budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Remaining: \(UsageFormatter.usdString(max(0, budget - spent)))")
                        .font(.caption)
                        .foregroundStyle(isOverBudget ? .red : .secondary)

                    if willExceedBudget && !isOverBudget {
                        Text("Projected to exceed budget")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if isOverBudget {
                        Text("Over budget by \(UsageFormatter.usdString(spent - budget))")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func budgetColor(ratio: Double) -> Color {
        if ratio >= 1.0 {
            return .red
        } else if ratio >= 0.8 {
            return .orange
        } else if ratio >= 0.6 {
            return .yellow
        } else {
            return self.providerColor
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
        }
    }

    private func saveBudget() {
        if let value = Double(self.budgetText), value > 0 {
            self.monthlyBudget = value
        } else if self.budgetText.isEmpty {
            self.monthlyBudget = nil
        }
        self.isEditingBudget = false
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
    struct PreviewWrapper: View {
        @State private var budget: Double? = 100.0

        var body: some View {
            UsageHistoryBudgetSection(
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
                provider: .claude,
                monthlyBudget: self.$budget)
                .padding()
                .frame(width: 500)
        }
    }

    return PreviewWrapper()
}
