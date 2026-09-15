import LittleSwitchCommon

/// Shared by inference, diagnostics and client catalog generation.
public enum ProviderResponsesWireResolver {
    public static func resolve(provider: Provider, learnedNative: Bool?) -> ModelImageInputWire {
        switch provider.responsesWireOverride {
        case .native:
            return .responses
        case .chatCompletions:
            return .chatCompletions
        case nil:
            if let learnedNative {
                return learnedNative ? .responses : .chatCompletions
            }
            return provider.wireProbe?.responsesRouteAbsent == true ? .chatCompletions : .responses
        }
    }
}
