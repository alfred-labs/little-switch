import Foundation
import LittleSwitchCommon

public enum ModelImageInputPolicyResolver {
    public static func key(
        provider: Provider, modelID: String, wire: ModelImageInputWire
    ) throws -> ModelImageInputKey {
        let api: ProviderEndpoint.ForwardingAPI = wire == .responses ? .responses : .chatCompletions
        return ModelImageInputKey(
            providerID: provider.id,
            modelID: modelID,
            wire: wire,
            endpoint: try ProviderEndpoint.forwarding(api, for: provider).absoluteString)
    }

    public static func acceptsImages(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        observations: [ModelImageInputObservation]
    ) throws -> Bool {
        switch provider.imageInputOverride {
        case .enabled: return true
        case .disabled: return false
        case nil: break
        }
        let key = try key(provider: provider, modelID: model.id, wire: wire)
        var latest: ModelImageInputObservation?
        for observation in observations where observation.key == key {
            if latest.map({ $0.observedAt <= observation.observedAt }) ?? true {
                latest = observation
            }
        }
        // Expiry schedules revalidation; it never changes the last known fact.
        return latest.map { $0.verdict == .verified } ?? provider.imageInputsAccepted(for: model)
    }
}
