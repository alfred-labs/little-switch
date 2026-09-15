import Foundation
import LittleSwitchCommon
import LittleSwitchCore

struct ProviderImageInputState: Equatable, Sendable {
    var progress: [UUID: ProviderImageProbeProgress] = [:]
    var diagnostics: [ModelImageInputProbeDiagnostic] = []
    var persistenceFailures: Set<UUID> = []
    var sequence: UInt64 = 0

    init() {}

    init(snapshot: CoordinatorSnapshot) {
        progress = snapshot.imageProbeProgress
        diagnostics = snapshot.imageInputDiagnostics
        persistenceFailures = snapshot.imageInputPersistenceFailures
        sequence = snapshot.monitoringSnapshotSequence
    }
}

/// Background updates change evidence only, never replace an editor or a client draft.
struct ProviderImageInputUpdate: Equatable, Sendable {
    let state: ProviderImageInputState
    let providers: [Provider]
    let codex: CodexConfiguration
    let openCode: OpenCodeConfiguration
    let codexPending: Bool
    let openCodePending: Bool

    init(snapshot: CoordinatorSnapshot) {
        state = ProviderImageInputState(snapshot: snapshot)
        providers = snapshot.configuration.providers
        codex = snapshot.configuration.codex
        openCode = snapshot.configuration.openCode
        codexPending = snapshot.hasPendingCodexChanges
        openCodePending = snapshot.hasPendingOpenCodeChanges
    }

    @MainActor func apply(to model: AppModel) {
        guard state.sequence >= model.imageInputState.sequence else { return }
        if model.imageInputState != state { model.imageInputState = state }
        for provider in providers {
            guard let index = model.configuration.providers.firstIndex(where: { $0.id == provider.id }),
                model.configuration.providers[index].hasSameImageInputIdentity(as: provider),
                model.configuration.providers[index].imageInputObservations != provider.imageInputObservations
            else { continue }
            model.configuration.providers[index].imageInputObservations = provider.imageInputObservations
        }
        if model.configuration.codex == codex { model.hasPendingCodexChanges = codexPending }
        if model.configuration.openCode == openCode { model.hasPendingOpenCodeChanges = openCodePending }
    }
}
