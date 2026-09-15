import Foundation
import LittleSwitchCommon

package protocol ModelImageProbeAdmitting: Sendable {
    func admit(eventID: UUID, provider: Provider, modelID: String) async throws
    func finish(eventID: UUID) async
}

/// Uses the gateway's actual provider pool. There is no unadmitted startup fallback.
package actor ModelImageProbeAdmission: ModelImageProbeAdmitting {
    private var state: GatewayState?
    private var owners: [UUID: GatewayState] = [:]

    package init() {}

    package func bind(_ state: GatewayState?) { self.state = state }

    package func admit(eventID: UUID, provider: Provider, modelID: String) async throws {
        guard let state else { throw GatewayAdmissionError.notAcceptingRequests }
        try await state.admitImageProbe(eventID: eventID, provider: provider, modelID: modelID)
        owners[eventID] = state
    }

    package func finish(eventID: UUID) async {
        await owners.removeValue(forKey: eventID)?.finish(eventID: eventID)
    }
}
