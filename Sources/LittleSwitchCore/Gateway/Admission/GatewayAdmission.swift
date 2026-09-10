import HTTPTypes
import Hummingbird

extension GatewayResponder {
    package enum AdmissionFailureKind: Sendable {
        case shutdown
        case queue
        case unexpected
    }

    package struct HandledAdmissionFailure: Swift.Error, Sendable {
        package let style: ErrorStyle
        package let kind: AdmissionFailureKind
    }

    package func admitRequest(
        _ request: GatewayRequestAdmission,
        errorStyle: ErrorStyle
    ) async throws {
        try Task.checkCancellation()
        do {
            try await dependencies.admitter.admit(state: state, request: request)
            await GatewayMonitoringScope.current?.admission(.admitted)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch GatewayState.Error.notAcceptingRequests {
            await GatewayMonitoringScope.current?.admission(.shutdown)
            throw HandledAdmissionFailure(style: errorStyle, kind: .shutdown)
        } catch let error as GatewayAdmissionError {
            let outcome: MonitoringAdmissionOutcome =
                switch error {
                case .overloaded: .overloaded
                case .timedOut: .timedOut
                case .invalidated: .invalidated
                case .notAcceptingRequests: .shutdown
                case .duplicateEventID, .invalidRetainedBodyBytes: .internalFailure
                }
            await GatewayMonitoringScope.current?.admission(outcome)
            switch error {
            case .overloaded, .timedOut, .invalidated:
                throw HandledAdmissionFailure(style: errorStyle, kind: .queue)
            case .notAcceptingRequests:
                throw HandledAdmissionFailure(style: errorStyle, kind: .shutdown)
            case .duplicateEventID, .invalidRetainedBodyBytes:
                throw HandledAdmissionFailure(style: errorStyle, kind: .unexpected)
            }
        } catch {
            await GatewayMonitoringScope.current?.admission(.internalFailure)
            throw HandledAdmissionFailure(style: errorStyle, kind: .unexpected)
        }
    }

    package func admissionFailureResponse(
        _ failure: HandledAdmissionFailure
    ) -> (response: Response, terminalFailure: TrafficFailure?) {
        switch failure.kind {
        case .shutdown:
            return (
                errorResponse(
                    style: failure.style,
                    status: .serviceUnavailable,
                    message: "Gateway is shutting down"
                ),
                nil
            )
        case .queue:
            return queueFailureResponse(style: failure.style)
        case .unexpected:
            return (
                errorResponse(
                    style: failure.style,
                    status: .internalServerError,
                    message: "Could not admit request"
                ),
                TrafficFailure(kind: "gateway", message: "Gateway response failed")
            )
        }
    }

    private func queueFailureResponse(
        style: ErrorStyle
    ) -> (response: Response, terminalFailure: TrafficFailure?) {
        var headers = HTTPFields()
        headers[.retryAfter] = "30"
        let message = "Provider request queue is temporarily unavailable"
        let response =
            switch style {
            case .anthropic:
                anthropicError(
                    status: .serviceUnavailable,
                    message: message,
                    errorType: "overloaded_error",
                    headers: headers
                )
            case .openAI:
                openAIError(
                    status: .serviceUnavailable,
                    message: message,
                    errorType: "server_error",
                    headers: headers
                )
            }
        return (
            response,
            TrafficFailure(kind: "queue", message: "Provider request queue unavailable")
        )
    }
}
