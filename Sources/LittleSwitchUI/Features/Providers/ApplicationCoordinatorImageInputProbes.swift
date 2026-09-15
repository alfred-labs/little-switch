import Foundation
import LittleSwitchCommon
import LittleSwitchCore

extension ApplicationCoordinator {
    package func initializeImageInputProbing() async {
        guard !imageProbeHandlersInstalled else { return }
        imageProbeHandlersInstalled = true
        await imageInputRegistry.setHandlers(
            onObservation: { [weak self] observation, generation in
                await self?.acceptImageInputObservation(observation, generation: generation)
            },
            onProbeDiagnostic: { [weak self] diagnostic, generation in
                await self?.acceptImageInputDiagnostic(diagnostic, generation: generation)
            })
    }

    package func synchronizeImageInputContext(providerID: UUID, credentialChanged: Bool = false) async {
        guard let provider = configuration.providers.first(where: { $0.id == providerID }) else {
            await cancelImageInputProbes(providerID: providerID)
            return
        }
        let sameIdentity = imageProbeProviders[providerID]?.hasSameImageInputIdentity(as: provider) == true
        let changedSecret = credentialChanged && provider.credentialSource == .manual
        if !sameIdentity || changedSecret || imageProbeGenerations[providerID] == nil {
            // Advance before any await; callbacks already queued on this actor carry the old epoch.
            imageProbeGenerations[providerID] = UUID()
            imageProbeBatches.removeValue(forKey: providerID)?.task.cancel()
            imageProbeProgress[providerID] = nil
            imageInputDiagnostics.removeAll { $0.key.providerID == providerID }
            imageInputPersistenceFailures.remove(providerID)
        }
        imageProbeProviders[providerID] = provider
        let generation = imageProbeGenerations[providerID].unsafelyUnwrapped
        do {
            try await imageInputRegistry.configure(provider: provider, generation: generation)
        } catch {
            imageInputPersistenceFailures.insert(providerID)
        }
    }

    package func activateImageInputProbing() async {
        await initializeImageInputProbing()
        let state = gatewayState
        await imageProbeAdmission.bind(state)
        guard let state, gatewayState === state else { return }
        imageProbesReady = true
        for id in pendingImageProbeProviders { await scheduleImageInputProbes(providerID: id) }
    }

    package func scheduleImageInputProbes(providerID: UUID, preferredModelIDs: [String] = []) async {
        guard imageProbeBatches[providerID] == nil,
            let provider = configuration.providers.first(where: { $0.id == providerID }), provider.status == .ready
        else { return }
        pendingImageProbeProviders.insert(providerID)
        await initializeImageInputProbing()
        guard imageProbesReady, gatewayState != nil, let generation = imageProbeGenerations[providerID] else { return }
        let wire = ProviderResponsesWireResolver.resolve(
            provider: provider, learnedNative: await responsesCapabilities.verdicts()[providerID])
        let preferred = preferredModelIDs + preferredImageProbeModelIDs(providerID: providerID)
        let models =
            (try? await imageInputRegistry.candidates(
                provider: provider, preferredModelIDs: preferred, wire: wire)) ?? []
        guard imageProbesReady, imageProbeGenerations[providerID] == generation,
            imageProbeBatches[providerID] == nil
        else { return }
        pendingImageProbeProviders.remove(providerID)
        guard !models.isEmpty else { return }
        let token = UUID()
        imageProbeProgress[providerID] = ProviderImageProbeProgress(total: models.count, running: true)
        let task = Task { [weak self] in
            for model in models {
                if Task.isCancelled { break }
                await self?.performImageInputProbe(
                    providerID: providerID, model: model, wire: wire, generation: generation)
            }
            await self?.finishImageProbeBatch(providerID: providerID, token: token)
        }
        imageProbeBatches[providerID] = ProviderImageProbeBatch(token: token, task: task)
    }

    private func performImageInputProbe(
        providerID: UUID, model: DiscoveredModel, wire: ModelImageInputWire, generation: UUID
    ) async {
        guard let state = gatewayState, imageProbeGenerations[providerID] == generation,
            let provider = configuration.providers.first(where: { $0.id == providerID })
        else { return }
        do {
            let capture = await state.routingCapture()
            let secret = try await state.providerCredential(
                providerID: providerID, capture: capture, secretStore: secretStore)
            try Task.checkCancellation()
            _ = try await imageInputRegistry.probeIfNeeded(
                provider: provider, model: model, wire: wire, secret: secret, generation: generation)
        } catch {
            // Admission/cancellation is not evidence about vision or connection health.
        }
        if imageProbeGenerations[providerID] == generation, !Task.isCancelled {
            imageProbeProgress[providerID]?.completed += 1
        }
    }

    private func finishImageProbeBatch(providerID: UUID, token: UUID) {
        guard imageProbeBatches[providerID]?.token == token else { return }
        imageProbeBatches[providerID] = nil
        imageProbeProgress[providerID]?.running = false
    }

    package func cancelImageInputProbes(providerID: UUID) async {
        imageProbeGenerations[providerID] = nil
        imageProbeProviders[providerID] = nil
        imageProbeBatches.removeValue(forKey: providerID)?.task.cancel()
        pendingImageProbeProviders.remove(providerID)
        imageProbeProgress[providerID] = nil
        imageInputDiagnostics.removeAll { $0.key.providerID == providerID }
        imageInputPersistenceFailures.remove(providerID)
        await imageInputRegistry.invalidate(providerID: providerID)
    }

    package func suspendImageInputProbes() {
        imageProbesReady = false
        for (id, batch) in imageProbeBatches {
            batch.task.cancel()
            pendingImageProbeProviders.insert(id)
            imageProbeProgress[id]?.running = false
        }
        imageProbeBatches.removeAll()
    }

    package func preferredImageProbeModelIDs(providerID: UUID) -> [String] {
        let defaults = [
            configuration.codex.resolvedDefaultModel(in: configuration.providers),
            configuration.openCode.defaultModel,
        ].compactMap { mapping in
            mapping.flatMap { $0.providerID == providerID ? $0.modelID : nil }
        }
        let mapped = configuration.mappings.values.filter { $0.providerID == providerID }.map(\.modelID).sorted()
        let exposed = configuration.codex.exposedModels(in: configuration.providers)
            .filter { $0.provider.id == providerID }
            .map(\.model.id)
        return defaults + mapped + exposed
    }
}
