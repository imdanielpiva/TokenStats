import SwiftUI
import TokenStatsCore

/// Main window view for TokenStats desktop app.
/// Uses NavigationSplitView with provider sidebar and detail view.
struct MainWindowView: View {
    @Bindable var usageStore: UsageStore
    @Bindable var settings: SettingsStore
    @State private var selectedProvider: UsageProvider?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var enabledProviders: [UsageProvider] {
        self.usageStore.enabledProviders()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: self.$columnVisibility) {
            MainWindowSidebar(
                usageStore: self.usageStore,
                settings: self.settings,
                selectedProvider: self.$selectedProvider)
        } detail: {
            if let provider = self.selectedProvider {
                MainWindowDetailView(
                    provider: provider,
                    usageStore: self.usageStore,
                    settings: self.settings)
            } else {
                self.emptyDetailView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await self.usageStore.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh usage data for all providers")
            }
        }
        .task {
            // Select first enabled provider on launch
            if self.selectedProvider == nil, let first = self.enabledProviders.first {
                self.selectedProvider = first
            }
        }
        .onChange(of: self.enabledProviders) { _, newProviders in
            // If selected provider is no longer enabled, select first available
            if let selected = self.selectedProvider, !newProviders.contains(selected) {
                self.selectedProvider = newProviders.first
            }
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Provider Selected")
                .font(.title2)
                .fontWeight(.medium)

            if self.enabledProviders.isEmpty {
                Text("Enable providers in Settings to view usage data.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Select a provider from the sidebar.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
