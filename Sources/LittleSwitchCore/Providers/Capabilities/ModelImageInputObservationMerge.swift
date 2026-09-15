import Foundation
import LittleSwitchCommon

public enum ModelImageInputObservationMerge {
    public static func merge(
        existing: [ModelImageInputObservation],
        incoming: [ModelImageInputObservation],
        validKeys: Set<ModelImageInputKey>
    ) -> [ModelImageInputObservation] {
        var latest: [ModelImageInputKey: ModelImageInputObservation] = [:]
        for observation in existing + incoming where validKeys.contains(observation.key) {
            if latest[observation.key].map({ $0.observedAt <= observation.observedAt }) ?? true {
                latest[observation.key] = observation
            }
        }
        return latest.values.sorted {
            ($0.key.providerID.uuidString, $0.key.modelID, $0.key.wire.rawValue, $0.key.endpoint)
                < ($1.key.providerID.uuidString, $1.key.modelID, $1.key.wire.rawValue, $1.key.endpoint)
        }
    }

    public static func validKeys(provider: Provider) throws -> Set<ModelImageInputKey> {
        var keys: Set<ModelImageInputKey> = []
        for model in provider.models {
            for wire in [ModelImageInputWire.responses, .chatCompletions] {
                keys.insert(try ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: wire))
            }
        }
        return keys
    }
}
