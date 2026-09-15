import Foundation
import LittleSwitchCore

extension ApplicationCoordinator {
    /// Learned Responses-wire verdicts from the live gateway state: true means
    /// the provider serves `/v1/responses` natively, false means the
    /// chat-completions adapter took over. Empty while the gateway is down or
    /// nothing has been probed yet.
    public func responsesWireVerdicts() async -> [UUID: Bool] {
        catalogResponsesWireVerdicts = await gatewayState?.responsesCapabilityVerdicts() ?? [:]
        return catalogResponsesWireVerdicts
    }
}
