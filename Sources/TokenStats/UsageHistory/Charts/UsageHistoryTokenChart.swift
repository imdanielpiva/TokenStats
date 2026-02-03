import Charts
import TokenStatsCore
import SwiftUI

/// Bar chart showing token usage over time.
struct UsageHistoryTokenChart: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    @State private var selectedEntryId: String?

    private var trendLinePoints: [(label: String, value: Double)] {
        let data = self.entries
        guard data.count >= 2 else { return [] }

        let n = Double(data.count)
        let xs = data.enumerated().map { Double($0.offset) }
        let ys = data.map { Double($0.totalTokens) }

        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return [] }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        return data.enumerated().map { index, entry in
            (label: entry.periodLabel, value: max(0, intercept + slope * Double(index)))
        }
    }

    var body: some View {
        if self.entries.isEmpty {
            self.emptyView
        } else {
            self.chartView
        }
    }

    private var emptyView: some View {
        Text("No token data")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(self.entries) { entry in
                    BarMark(
                        x: .value("Period", entry.periodLabel),
                        y: .value("Tokens", entry.totalTokens))
                        .foregroundStyle(self.barColor.opacity(self.selectedEntryId == entry.id ? 1.0 : 0.8))
                }

                ForEach(Array(self.trendLinePoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Period", point.label),
                        y: .value("Trend", point.value))
                        .foregroundStyle(self.barColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .interpolationMethod(.linear)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(self.entries.count, 10))) { _ in
                    AxisGridLine()
                    AxisTick()
                    if self.entries.count <= 30 {
                        AxisValueLabel()
                            .font(.caption2)
                    }
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
                                self.selectedEntryId = nil
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
        if let id = self.selectedEntryId, let entry = self.entries.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.periodLabel): \(UsageFormatter.tokenCountString(entry.totalTokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !entry.modelsUsed.isEmpty {
                    Text("Models: \(entry.modelsUsed.prefix(3).map { UsageFormatter.modelDisplayName($0) }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } else {
            Text("Hover a bar for details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var barColor: Color {
        switch self.provider {
        case .claude:
            Color(red: 0.84, green: 0.45, blue: 0.28) // Claude orange
        case .codex:
            Color(red: 0.10, green: 0.65, blue: 0.45) // Codex green
        case .vertexai:
            Color(red: 0.25, green: 0.52, blue: 0.96) // Google blue
        case .amp:
            Color(red: 0.95, green: 0.31, blue: 0.25) // Amp red
        }
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

        // Find matching entry
        if let entry = self.entries.first(where: { $0.periodLabel == label }) {
            self.selectedEntryId = entry.id
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
    UsageHistoryTokenChart(
        entries: [
            CostUsageAggregatedEntry(
                id: "2025-01",
                periodLabel: "Jan 2025",
                periodStart: Date(),
                periodEnd: Date(),
                inputTokens: 500_000,
                outputTokens: 200_000,
                cacheReadTokens: 100_000,
                cacheCreationTokens: 50_000,
                totalTokens: 850_000,
                costUSD: 12.50,
                modelsUsed: ["claude-opus-4-5"],
                modelBreakdowns: []),
            CostUsageAggregatedEntry(
                id: "2025-02",
                periodLabel: "Feb 2025",
                periodStart: Date(),
                periodEnd: Date(),
                inputTokens: 600_000,
                outputTokens: 250_000,
                cacheReadTokens: 120_000,
                cacheCreationTokens: 60_000,
                totalTokens: 1_030_000,
                costUSD: 15.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
        ],
        provider: .claude)
        .frame(height: 250)
        .padding()
}
