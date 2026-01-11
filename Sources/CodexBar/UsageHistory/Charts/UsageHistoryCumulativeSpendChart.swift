import Charts
import CodexBarCore
import SwiftUI

/// Line chart showing cumulative spend over time.
struct UsageHistoryCumulativeSpendChart: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    @State private var selectedEntryId: String?

    private var cumulativeData: [(entry: CostUsageAggregatedEntry, cumulative: Double)] {
        var running: Double = 0
        return self.entriesWithCost.map { entry in
            running += entry.costUSD ?? 0
            return (entry: entry, cumulative: running)
        }
    }

    private var entriesWithCost: [CostUsageAggregatedEntry] {
        self.entries.filter { $0.costUSD != nil }
    }

    private var totalCost: Double {
        self.cumulativeData.last?.cumulative ?? 0
    }

    var body: some View {
        if self.entriesWithCost.isEmpty {
            self.emptyView
        } else {
            self.chartView
        }
    }

    private var emptyView: some View {
        Text("No cost data")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(self.cumulativeData, id: \.entry.id) { item in
                    AreaMark(
                        x: .value("Period", item.entry.periodLabel),
                        y: .value("Cumulative", item.cumulative))
                        .foregroundStyle(self.areaGradient)
                        .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Period", item.entry.periodLabel),
                        y: .value("Cumulative", item.cumulative))
                        .foregroundStyle(self.lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Period", item.entry.periodLabel),
                        y: .value("Cumulative", item.cumulative))
                        .foregroundStyle(self.selectedEntryId == item.entry.id ? self.lineColor : .clear)
                        .symbolSize(self.selectedEntryId == item.entry.id ? 60 : 0)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(self.entriesWithCost.count, 10))) { _ in
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
                        if let cost = value.as(Double.self) {
                            Text(UsageFormatter.usdString(cost))
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
                                self.selectedEntryId = nil
                            }
                        }
                }
            }

            // Detail text
            self.detailText
                .frame(height: 40)
        }
    }

    @ViewBuilder
    private var detailText: some View {
        if let id = self.selectedEntryId,
           let item = self.cumulativeData.first(where: { $0.entry.id == id })
        {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(item.entry.periodLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Day: \(UsageFormatter.usdString(item.entry.costUSD ?? 0))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("Total: \(UsageFormatter.usdString(item.cumulative))")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                // Show percentage of total
                if self.totalCost > 0 {
                    let pct = item.cumulative / self.totalCost * 100
                    Text("\(Int(pct))% of period total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("Hover to see running total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lineColor: Color {
        switch self.provider {
        case .claude:
            Color(red: 0.84, green: 0.45, blue: 0.28)
        case .codex:
            Color(red: 0.10, green: 0.65, blue: 0.45)
        case .vertexai:
            Color(red: 0.25, green: 0.52, blue: 0.96)
        }
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [self.lineColor.opacity(0.3), self.lineColor.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom)
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        guard frame.contains(location) else {
            self.selectedEntryId = nil
            return
        }

        let xInPlot = location.x - frame.origin.x
        guard let label: String = proxy.value(atX: xInPlot) else { return }

        if let item = self.cumulativeData.first(where: { $0.entry.periodLabel == label }) {
            self.selectedEntryId = item.entry.id
        }
    }
}

#Preview {
    UsageHistoryCumulativeSpendChart(
        entries: [
            CostUsageAggregatedEntry(
                id: "2025-01-01",
                periodLabel: "Jan 1",
                periodStart: Date(),
                periodEnd: Date(),
                inputTokens: 100_000,
                outputTokens: 50_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 150_000,
                costUSD: 5.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-01-02",
                periodLabel: "Jan 2",
                periodStart: Date(),
                periodEnd: Date(),
                inputTokens: 200_000,
                outputTokens: 100_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 300_000,
                costUSD: 8.50,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-01-03",
                periodLabel: "Jan 3",
                periodStart: Date(),
                periodEnd: Date(),
                inputTokens: 150_000,
                outputTokens: 75_000,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                totalTokens: 225_000,
                costUSD: 6.25,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
        ],
        provider: .claude)
        .frame(height: 250)
        .padding()
}
