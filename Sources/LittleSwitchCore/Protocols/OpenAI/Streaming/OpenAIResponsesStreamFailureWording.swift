import Foundation

extension ResponsesPublicStreamSession {
    /// A closed set of gateway-authored messages: identify known failures
    /// without publishing provider text, tool names, or tool arguments.
    package enum FailureWording: Sendable {
        case internalServerError
        case withoutProviderPayload
        case upstreamEndedBeforeCompletion
        case undeclaredTool(UUID)

        init(error: any Swift.Error, eventID: UUID) {
            if case .undeclaredTool = error as? ProviderToolContract.Error {
                self = .undeclaredTool(eventID)
            } else {
                self = .internalServerError
            }
        }

        var text: String {
            switch self {
            case .internalServerError:
                "Internal server error"
            case .withoutProviderPayload:
                "The provider failed the response without an error payload."
            case .upstreamEndedBeforeCompletion:
                "Upstream stream ended before completion"
            case .undeclaredTool(let eventID):
                "The provider called a tool that was not allowed by the request."
                    + " Error ID: \(eventID.uuidString)"
            }
        }
    }
}
