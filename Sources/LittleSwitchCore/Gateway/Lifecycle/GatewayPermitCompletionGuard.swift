import Foundation

package final class GatewayPermitCompletionGuard: Sendable {
    private let state: GatewayState
    private let eventID: UUID
    private let monitoring: MonitoringRequestContext?

    package init(state: GatewayState, eventID: UUID, monitoring: MonitoringRequestContext? = nil) {
        self.state = state
        self.eventID = eventID
        self.monitoring = monitoring
    }

    deinit {
        let state = state
        let eventID = eventID
        let monitoring = monitoring
        Task {
            await state.finish(eventID: eventID)
            await monitoring?.finish(error: .cancelled)
        }
    }

    package func finish() async {
        await state.finish(eventID: eventID)
    }
}
