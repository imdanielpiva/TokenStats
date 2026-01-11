import TokenStatsMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum AmpProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .amp,
            metadata: ProviderMetadata(
                id: .amp,
                displayName: "Amp",
                sessionLabel: "Today",
                weeklyLabel: "Total",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: true,
                creditsHint: "$10/day grant",
                toggleTitle: "Show Amp usage",
                cliName: "amp",
                defaultEnabled: true,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: "https://ampcode.com",
                statusPageURL: nil,
                statusLinkURL: "https://status.ampcode.com"),
            branding: ProviderBranding(
                iconStyle: .amp,
                iconResourceName: "ProviderIcon-amp",
                color: ProviderColor(red: 243 / 255, green: 78 / 255, blue: 63 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: { "No Amp threads found. Run 'amp' to create your first thread." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [AmpLocalFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "amp",
                versionDetector: { _ in ProviderVersionDetector.ampVersion() }))
    }
}

struct AmpLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "amp.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        FileManager.default.fileExists(atPath: AmpStatusProbe.threadsPath)
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let probe = AmpStatusProbe()
        let snap = try await probe.fetch()
        return self.makeResult(
            usage: snap.toUsageSnapshot(),
            sourceLabel: "local")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
