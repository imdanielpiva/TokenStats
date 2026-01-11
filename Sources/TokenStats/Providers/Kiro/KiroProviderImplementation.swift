import TokenStatsCore
import TokenStatsMacroSupport
import Foundation

@ProviderImplementationRegistration
struct KiroProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .kiro
}
