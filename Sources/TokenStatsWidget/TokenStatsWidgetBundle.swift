import SwiftUI
import WidgetKit

@main
struct TokenStatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenStatsSwitcherWidget()
        TokenStatsUsageWidget()
        TokenStatsHistoryWidget()
        TokenStatsCompactWidget()
    }
}

struct TokenStatsSwitcherWidget: Widget {
    private let kind = "TokenStatsSwitcherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: TokenStatsSwitcherTimelineProvider())
        { entry in
            TokenStatsSwitcherWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Switcher")
        .description("Usage widget with a provider switcher.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TokenStatsUsageWidget: Widget {
    private let kind = "TokenStatsUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: TokenStatsTimelineProvider())
        { entry in
            TokenStatsUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Usage")
        .description("Session and weekly usage with credits and costs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TokenStatsHistoryWidget: Widget {
    private let kind = "TokenStatsHistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: TokenStatsTimelineProvider())
        { entry in
            TokenStatsHistoryWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar History")
        .description("Usage history chart with recent totals.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TokenStatsCompactWidget: Widget {
    private let kind = "TokenStatsCompactWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: CompactMetricSelectionIntent.self,
            provider: TokenStatsCompactTimelineProvider())
        { entry in
            TokenStatsCompactWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Metric")
        .description("Compact widget for credits or cost.")
        .supportedFamilies([.systemSmall])
    }
}
