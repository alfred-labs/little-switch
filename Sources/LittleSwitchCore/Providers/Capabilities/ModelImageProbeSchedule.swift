import Foundation
import LittleSwitchCommon

package enum ModelImageProbeSchedule {
    package static let observationTTL: TimeInterval = 7 * 24 * 60 * 60
    package static let inconclusiveCooldown: TimeInterval = 60 * 60

    package static func candidates(
        provider: Provider,
        preferredModelIDs: [String],
        wire: ModelImageInputWire,
        observations: [ModelImageInputObservation],
        now: Date,
        limit: Int = 4
    ) throws -> [DiscoveredModel] {
        guard limit > 0, provider.imageInputOverride == nil else { return [] }
        var seen: Set<String> = []
        let ordered = provider.models.sorted {
            let left = preferredModelIDs.firstIndex(of: $0.id) ?? Int.max
            let right = preferredModelIDs.firstIndex(of: $1.id) ?? Int.max
            return (left, $0.id) < (right, $1.id)
        }
        let eligible = try ordered.filter { model in
            guard seen.insert(model.id).inserted else { return false }
            let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: wire)
            let observation = observations.filter { $0.key == key }.max { $0.observedAt < $1.observedAt }
            if let observation, now.timeIntervalSince(observation.observedAt) < observationTTL { return false }
            if let advertised = model.supportsImageInput {
                return observation.map { ($0.verdict == .verified) != advertised } ?? false
            }
            return true
        }
        return Array(eligible.prefix(limit))
    }
}
