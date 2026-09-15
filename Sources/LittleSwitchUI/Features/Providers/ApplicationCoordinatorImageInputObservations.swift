import Foundation
import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    /// Client transactions may suspend while a background check commits. Their older
    /// candidate must keep the current durable evidence, including a credential invalidation.
    package func retainingCurrentImageObservations(in candidate: AppConfiguration) -> AppConfiguration {
        var candidate = candidate
        for index in candidate.providers.indices {
            let provider = candidate.providers[index]
            guard let current = configuration.providers.first(where: { $0.id == provider.id }),
                current.hasSameImageInputIdentity(as: provider)
            else { continue }
            let modelIDs = Set(provider.models.map(\.id))
            candidate.providers[index].imageInputObservations = current.imageInputObservations.filter {
                modelIDs.contains($0.key.modelID)
            }
        }
        return candidate
    }

    package func imageInputObservationsForProvider(
        _ provider: Provider,
        previous: Provider?,
        credentialChanged: Bool
    ) throws -> [ModelImageInputObservation] {
        let validKeys = try ModelImageInputObservationMerge.validKeys(provider: provider)
        guard let previous,
            previous.hasSameImageInputIdentity(as: provider),
            !(credentialChanged && provider.credentialSource == .manual)
        else { return [] }
        return ModelImageInputObservationMerge.merge(
            existing: previous.imageInputObservations,
            incoming: [],
            validKeys: validKeys)
    }

    package func acceptImageInputObservation(_ observation: ModelImageInputObservation, generation: UUID) async {
        let id = observation.key.providerID
        guard imageProbeGenerations[id] == generation,
            let index = configuration.providers.firstIndex(where: { $0.id == id }),
            let validKeys = try? ModelImageInputObservationMerge.validKeys(provider: configuration.providers[index]),
            validKeys.contains(observation.key)
        else { return }
        var candidate = configuration
        candidate.providers[index].imageInputObservations = ModelImageInputObservationMerge.merge(
            existing: candidate.providers[index].imageInputObservations, incoming: [observation], validKeys: validKeys)
        guard candidate != configuration else { return }
        do {
            try configurationStore.save(candidate)
            configuration = candidate
            imageInputPersistenceFailures.remove(id)
            await replaceGatewayRoutingIfNeeded()
        } catch {
            imageInputPersistenceFailures.insert(id)
        }
    }

    package func acceptImageInputDiagnostic(_ diagnostic: ModelImageInputProbeDiagnostic, generation: UUID) {
        let id = diagnostic.key.providerID
        guard imageProbeGenerations[id] == generation,
            let provider = configuration.providers.first(where: { $0.id == id }),
            (try? ModelImageInputObservationMerge.validKeys(provider: provider).contains(diagnostic.key)) == true
        else { return }
        imageInputDiagnostics.removeAll { $0.key == diagnostic.key }
        imageInputDiagnostics.append(diagnostic)
    }
}
