import Foundation
import LittleSwitchCommon

/// Session evidence and owned probe jobs. Persistence belongs to the application coordinator.
package actor ModelImageInputRegistry {
    static let maximumWaiters = 128

    struct Context: Sendable {
        let provider: Provider
        let generation: UUID
        let validKeys: Set<ModelImageInputKey>
    }

    struct Job: Sendable {
        let key: ModelImageInputKey
        let provider: Provider
        let model: DiscoveredModel
        let generation: UUID
        let secret: String?
        var waiters: [UUID: CheckedContinuation<ModelImageInputProbeResult?, any Error>]
        var task: Task<Void, Never>?
    }

    let prober: any ModelImageInputProbing
    let admission: any ModelImageProbeAdmitting
    let now: @Sendable () -> Date
    var contexts: [UUID: Context] = [:]
    var evidence: [ModelImageInputKey: ModelImageInputObservation] = [:]
    var cooldowns: [ModelImageInputKey: Date] = [:]
    var jobs: [UUID: Job] = [:]
    var jobsByKey: [ModelImageInputKey: UUID] = [:]
    var queue: [UUID] = []
    var stopped = false
    var onObservation: @Sendable (ModelImageInputObservation, UUID) async -> Void = { _, _ in }
    var onDiagnostic: @Sendable (ModelImageInputProbeDiagnostic, UUID) async -> Void = { _, _ in }

    package init(
        prober: any ModelImageInputProbing,
        admission: any ModelImageProbeAdmitting,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.prober = prober
        self.admission = admission
        self.now = now
    }

    package func setHandlers(
        onObservation: @escaping @Sendable (ModelImageInputObservation, UUID) async -> Void,
        onProbeDiagnostic: @escaping @Sendable (ModelImageInputProbeDiagnostic, UUID) async -> Void
    ) {
        self.onObservation = onObservation
        onDiagnostic = onProbeDiagnostic
    }

    package func configure(provider: Provider, generation: UUID) throws {
        let validKeys = try ModelImageInputObservationMerge.validKeys(provider: provider)
        if let old = contexts[provider.id] {
            if old.generation != generation || !old.provider.hasSameImageInputIdentity(as: provider) {
                invalidate(providerID: provider.id)
            }
        }
        contexts[provider.id] = Context(provider: provider, generation: generation, validKeys: validKeys)
        for (id, job) in jobs where job.key.providerID == provider.id {
            if !validKeys.contains(job.key) || provider.imageInputOverride != nil { cancelJob(id) }
        }
        let otherKeys = Set(evidence.keys.filter { $0.providerID != provider.id })
        let merged = ModelImageInputObservationMerge.merge(
            existing: Array(evidence.values),
            incoming: provider.imageInputObservations,
            validKeys: validKeys.union(otherKeys))
        evidence = Dictionary(uniqueKeysWithValues: merged.map { ($0.key, $0) })
        cooldowns = cooldowns.filter { $0.key.providerID != provider.id || validKeys.contains($0.key) }
    }

    package func generation(providerID: UUID) -> UUID? { contexts[providerID]?.generation }

    package func observations(providerID: UUID, generation: UUID?) -> [ModelImageInputObservation] {
        guard let generation, contexts[providerID]?.generation == generation else { return [] }
        return evidence.values.filter { $0.key.providerID == providerID }
    }

    package func candidates(
        provider: Provider, preferredModelIDs: [String], wire: ModelImageInputWire, limit: Int = 4
    ) throws -> [DiscoveredModel] {
        let instant = now()
        let eligible = try ModelImageProbeSchedule.candidates(
            provider: provider,
            preferredModelIDs: preferredModelIDs,
            wire: wire,
            observations: Array(evidence.values),
            now: instant,
            limit: Int.max)
        let ready = try eligible.filter { model in
            let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: wire)
            return cooldowns[key].map { instant >= $0 } ?? true
        }
        return Array(ready.prefix(max(0, limit)))
    }

    package func record(_ observation: ModelImageInputObservation, generation: UUID) async {
        guard isCurrent(observation.key, generation: generation) else { return }
        if let previous = evidence[observation.key] {
            guard previous.observedAt <= observation.observedAt else { return }
            let fresh = now().timeIntervalSince(previous.observedAt) < ModelImageProbeSchedule.observationTTL
            if previous.verdict == observation.verdict && fresh { return }
        }
        evidence[observation.key] = observation
        cooldowns[observation.key] = nil
        await onObservation(observation, generation)
    }

    package func invalidate(providerID: UUID) {
        contexts[providerID] = nil
        for (id, job) in jobs where job.key.providerID == providerID { cancelJob(id) }
        evidence = evidence.filter { $0.key.providerID != providerID }
        cooldowns = cooldowns.filter { $0.key.providerID != providerID }
    }

    package func shutdown() async {
        stopped = true
        let tasks = jobs.values.compactMap(\.task)
        for id in Array(jobs.keys) { cancelJob(id) }
        for task in tasks { await task.value }
    }

    package var waiterCount: Int { jobs.values.reduce(0) { $0 + $1.waiters.count } }

    func isCurrent(_ key: ModelImageInputKey, generation: UUID) -> Bool {
        !stopped && contexts[key.providerID]?.generation == generation
            && contexts[key.providerID]?.validKeys.contains(key) == true
    }
}
