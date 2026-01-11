@attached(peer, names: prefixed(_TokenStatsDescriptorRegistration_))
public macro ProviderDescriptorRegistration() = #externalMacro(
    module: "TokenStatsMacros",
    type: "ProviderDescriptorRegistrationMacro")

@attached(member, names: named(descriptor))
public macro ProviderDescriptorDefinition() = #externalMacro(
    module: "TokenStatsMacros",
    type: "ProviderDescriptorDefinitionMacro")

@attached(peer, names: prefixed(_TokenStatsImplementationRegistration_))
public macro ProviderImplementationRegistration() = #externalMacro(
    module: "TokenStatsMacros",
    type: "ProviderImplementationRegistrationMacro")
