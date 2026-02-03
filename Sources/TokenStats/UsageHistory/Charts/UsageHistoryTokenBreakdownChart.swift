import Charts
import TokenStatsCore
import SwiftUI

/// Stacked bar chart showing input vs output token breakdown over time.
struct UsageHistoryTokenBreakdownChart: View {
    let entries: [CostUsageAggregatedEntry]
    let provider: UsageHistoryProvider

    @State private var selectedEntryId: String?

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
                    // Output tokens (stacked on top)
                    BarMark(
                        x: .value("Period", entry.periodLabel),
                        y: .value("Tokens", entry.outputTokens))
                        .foregroundStyle(self.outputColor.opacity(self.selectedEntryId == entry.id ? 1.0 : 0.8))
                        .position(by: .value("Type", "Output"))

                    // Input tokens (bottom)
                    BarMark(
                        x: .value("Period", entry.periodLabel),
                        y: .value("Tokens", entry.inputTokens))
                        .foregroundStyle(self.inputColor.opacity(self.selectedEntryId == entry.id ? 1.0 : 0.8))
                        .position(by: .value("Type", "Input"))
                }
            }
            .chartForegroundStyleScale([
                "Input": self.inputColor,
                "Output": self.outputColor,
            ])
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

            // Legend
            HStack(spacing: 16) {
                self.legendItem(color: self.inputColor, label: "Input")
                self.legendItem(color: self.outputColor, label: "Output")
            }
            .font(.caption2)

            // Detail text
            self.detailText
                .frame(height: 32)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailText: some View {
        if let id = self.selectedEntryId, let entry = self.entries.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.periodLabel): \(UsageFormatter.tokenCountString(entry.inputTokens + entry.outputTokens)) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text("Input: \(UsageFormatter.tokenCountString(entry.inputTokens))")
                    Text("Output: \(UsageFormatter.tokenCountString(entry.outputTokens))")

                    if entry.inputTokens + entry.outputTokens > 0 {
                        let outputRatio = Double(entry.outputTokens) / Double(entry.inputTokens + entry.outputTokens) * 100
                        Text("(\(Int(outputRatio))% output)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        } else {
            Text("Hover a bar for input/output breakdown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inputColor: Color {
        switch self.provider {
        case .claude:
            Color(red: 0.84, green: 0.55, blue: 0.38) // Lighter Claude orange
        case .codex:
            Color(red: 0.20, green: 0.70, blue: 0.55) // Lighter Codex green
        case .vertexai:
            Color(red: 0.35, green: 0.60, blue: 0.96) // Lighter Google blue
        case .amp:
            Color(red: 0.97, green: 0.45, blue: 0.40) // Lighter Amp red
        }
    }

    private var outputColor: Color {
        switch self.provider {
        case .claude:
            Color(red: 0.70, green: 0.35, blue: 0.18) // Darker Claude orange
        case .codex:
            Color(red: 0.05, green: 0.55, blue: 0.35) // Darker Codex green
        case .vertexai:
            Color(red: 0.15, green: 0.42, blue: 0.86) // Darker Google blue
        case .amp:
            Color(red: 0.85, green: 0.20, blue: 0.15) // Darker Amp red
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
    UsageHistoryTokenBreakdownChart(
        entries: [
            CostUsageAggregatedEntry(
                id: "2025-01-08",
                periodLabel: "Jan 8",
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
                id: "2025-01-09",
                periodLabel: "Jan 9",
                periodStart: Date(),
                periodEnd: Date(),
                inputTokens: 600_000,
                outputTokens: 350_000,
                cacheReadTokens: 120_000,
                cacheCreationTokens: 60_000,
                totalTokens: 1_130_000,
                costUSD: 18.00,
                modelsUsed: ["claude-sonnet-4-5"],
                modelBreakdowns: []),
        ],
        provider: .claude)
        .frame(height: 250)
        .padding()
}
