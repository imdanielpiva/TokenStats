import TokenStatsCore
import TokenStatsMacroSupport
import Foundation

@ProviderImplementationRegistration
struct AmpProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .amp
    let supportsLoginFlow: Bool = false
}
