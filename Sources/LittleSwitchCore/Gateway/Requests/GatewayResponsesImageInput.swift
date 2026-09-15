import Foundation
import LittleSwitchCommon

extension GatewayResponder {
    /// Only called before business admission. Joining a diagnostic while holding the only permit deadlocks.
    package func probeResponsesImageInput(body: Data, target: CodexModelTarget, credential: String?) async throws {
        guard let registry = state.imageInputRegistry, let generation = responsesImageGeneration,
            try !ResponsesImageInputProjection.project(body: body, acceptsImages: true).imageItemIndices.isEmpty
        else { return }
        let wire: ModelImageInputWire =
            await resolvesChatCompletionsAdapter(target.provider) ? .chatCompletions : .responses
        do {
            _ = try await registry.probeIfNeeded(
                provider: target.provider, model: target.model, wire: wire, secret: credential, generation: generation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Unavailable diagnostic admission is not a statement about image capability.
            // The business admission still validates the captured provider revision.
        }
    }

    package func acceptsResponsesImages(
        target: CodexModelTarget,
        wire: ModelImageInputWire,
        forceText: Bool = false
    ) async throws -> Bool {
        if forceText { return false }
        let runtime =
            await state.imageInputRegistry?.observations(
                providerID: target.provider.id, generation: responsesImageGeneration) ?? []
        return try ModelImageInputPolicyResolver.acceptsImages(
            provider: target.provider,
            model: target.model,
            wire: wire,
            observations: target.provider.imageInputObservations + runtime)
    }

    /// Projects a request copy only; this method never acquires a diagnostic permit.
    package func responsesImageInput(
        body: Data,
        target: CodexModelTarget,
        wire: ModelImageInputWire,
        forceText: Bool = false
    ) async throws -> ResponsesImageInputProjection.Result {
        let original = try ResponsesImageInputProjection.project(body: body, acceptsImages: true)
        guard !original.imageItemIndices.isEmpty else { return original }
        if try await acceptsResponsesImages(target: target, wire: wire, forceText: forceText) { return original }
        return try ResponsesImageInputProjection.project(body: body, acceptsImages: false)
    }

    @discardableResult
    package func learnResponsesImageRejection(
        status: UInt,
        body: Data,
        target: CodexModelTarget,
        wire: ModelImageInputWire,
        hasImageInput: Bool
    ) async -> Bool {
        guard ModelImageInputRejection.matches(status: Int(clamping: status), body: body, hasImageInput: hasImageInput)
        else { return false }
        guard let generation = responsesImageGeneration,
            let key = try? ModelImageInputPolicyResolver.key(
                provider: target.provider, modelID: target.model.id, wire: wire)
        else { return true }
        await state.imageInputRegistry?.record(
            ModelImageInputObservation(
                key: key, verdict: .unsupported, source: .providerRejection, observedAt: Date()),
            generation: generation)
        return true
    }
}
