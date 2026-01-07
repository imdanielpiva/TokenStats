import Charts
import CodexBarCore
import SwiftUI

/// Bar chart showing cost over time.
struct UsageHistoryCostChart: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    @State private var selectedEntryId: String?

    private var entriesWithCost: [CostUsageAggregatedEntry] {
        self.entries.filter { $0.costUSD != nil && $0.costUSD! > 0 }
    }

    private var peakEntry: CostUsageAggregatedEntry? {
        self.entriesWithCost.max { ($0.costUSD ?? 0) < ($1.costUSD ?? 0) }
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
                ForEach(self.entriesWithCost) { entry in
                    BarMark(
                        x: .value("Period", entry.periodLabel),
                        y: .value("Cost", entry.costUSD ?? 0))
                        .foregroundStyle(self.barColor(for: entry))
                }

                // Peak highlight cap
                if let peak = self.peakEntry, let peakCost = peak.costUSD {
                    let capHeight = peakCost * 0.05
                    let capStart = max(peakCost - capHeight, 0)
                    BarMark(
                        x: .value("Period", peak.periodLabel),
                        yStart: .value("Cap start", capStart),
                        yEnd: .value("Cap end", peakCost))
                        .foregroundStyle(Color.yellow)
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
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                self.updateSelection(at: value.location, proxy: proxy, geo: geo)
                            }
                            .onEnded { _ in
                                self.selectedEntryId = nil
                            })
                }
            }

            // Detail text
            self.detailText
                .frame(height: 40)
        }
    }

    @ViewBuilder
    private var detailText: some View {
        if let id = self.selectedEntryId, let entry = self.entriesWithCost.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(entry.periodLabel): \(UsageFormatter.usdString(entry.costUSD ?? 0))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if entry.id == self.peakEntry?.id {
                        Text("Peak")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                if !entry.modelBreakdowns.isEmpty {
                    let topModels = entry.modelBreakdowns.prefix(3)
                    Text("Top: \(topModels.map { "\(UsageFormatter.modelDisplayName($0.modelName)) \(UsageFormatter.usdString($0.costUSD ?? 0))" }.joined(separator: " · "))")
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

    private func barColor(for entry: CostUsageAggregatedEntry) -> Color {
        let baseColor: Color
        switch self.provider {
        case .claude:
            baseColor = Color(red: 0.84, green: 0.45, blue: 0.28)
        case .codex:
            baseColor = Color(red: 0.10, green: 0.65, blue: 0.45)
        case .vertexai:
            baseColor = Color(red: 0.25, green: 0.52, blue: 0.96)
        }

        return baseColor.opacity(self.selectedEntryId == entry.id ? 1.0 : 0.8)
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

        if let entry = self.entriesWithCost.first(where: { $0.periodLabel == label }) {
            self.selectedEntryId = entry.id
        }
    }
}

#Preview {
    UsageHistoryCostChart(
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
                modelBreakdowns: [
                    CostUsageDailyReport.ModelBreakdown(modelName: "claude-opus-4-5", costUSD: 10.0),
                    CostUsageDailyReport.ModelBreakdown(modelName: "claude-sonnet-4-5", costUSD: 2.5),
                ]),
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
                costUSD: 25.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: [
                    CostUsageDailyReport.ModelBreakdown(modelName: "claude-sonnet-4-5", costUSD: 25.0),
                ]),
        ],
        provider: .claude)
        .frame(height: 250)
        .padding()
}
