import SwiftUI
import TokenStatsCore

/// Selection state for the main window sidebar.
enum MainWindowSelection: Hashable {
    case allProviders
    case provider(UsageProvider)

    var usageProvider: UsageProvider? {
        switch self {
        case .allProviders: nil
        case let .provider(p): p
        }
    }
}

/// Sidebar showing the list of enabled providers with status indicators.
struct MainWindowSidebar: View {
    @Bindable var usageStore: UsageStore
    @Bindable var settings: SettingsStore
    @Binding var selection: MainWindowSelection?

    private var enabledProviders: [UsageProvider] {
        self.usageStore.enabledProviders()
    }

    /// Show "All Providers" when 2+ providers have cost data
    private var showAllProviders: Bool {
        self.usageStore.combinedTokenSnapshot != nil
    }

    var body: some View {
        List(selection: self.$selection) {
            if self.showAllProviders {
                MainWindowAllProvidersRow(
                    usageStore: self.usageStore,
                    isSelected: self.selection == .allProviders)
                    .tag(MainWindowSelection.allProviders)
            }

            ForEach(self.enabledProviders, id: \.self) { provider in
                MainWindowSidebarRow(
                    provider: provider,
                    usageStore: self.usageStore,
                    isSelected: self.selection == .provider(provider))
                    .tag(MainWindowSelection.provider(provider))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Providers")
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)
    }
}

/// "All Providers" row showing combined cost summary.
struct MainWindowAllProvidersRow: View {
    @Bindable var usageStore: UsageStore
    let isSelected: Bool

    private var combinedSnapshot: CostUsageTokenSnapshot? {
        self.usageStore.combinedTokenSnapshot
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("All Providers")
                    .font(.body)
                    .fontWeight(self.isSelected ? .medium : .regular)

                if let snapshot = self.combinedSnapshot, let cost = snapshot.last30DaysCostUSD {
                    Text("\(UsageFormatter.usdString(cost)) / 30d")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Single row in the provider sidebar.
struct MainWindowSidebarRow: View {
    let provider: UsageProvider
    @Bindable var usageStore: UsageStore
    let isSelected: Bool

    private var metadata: ProviderMetadata {
        ProviderDescriptorRegistry.descriptor(for: self.provider).metadata
    }

    private var isRefreshing: Bool {
        self.usageStore.refreshingProviders.contains(self.provider)
    }

    private var hasError: Bool {
        self.usageStore.error(for: self.provider) != nil
    }

    private var usagePercent: Double? {
        guard let snapshot = self.usageStore.snapshot(for: self.provider) else { return nil }
        return snapshot.primary?.remainingPercent
    }

    var body: some View {
        HStack(spacing: 10) {
            self.providerIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.metadata.displayName)
                    .font(.body)
                    .fontWeight(self.isSelected ? .medium : .regular)

                if let percent = self.usagePercent {
                    Text("\(Int(percent))% remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            self.statusIndicator
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let nsImage = ProviderBrandIcon.image(for: self.provider) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if self.isRefreshing {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        } else if self.hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
