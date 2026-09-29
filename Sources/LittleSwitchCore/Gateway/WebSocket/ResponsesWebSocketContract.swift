/// WebSocket envelope and request options absent from the generated public
/// Responses projections. Projected provider fields use LittleSwitchWire keys.
package enum ResponsesWebSocketContract {
    package enum ErrorCode: String, Sendable {
        case invalidInput = "invalid_input"
        case invalidRequest = "invalid_request"
        case invalidRequestError = "invalid_request_error"
        case invalidResponse = "invalid_response"
        case invalidStreamID = "invalid_stream_id"
        case modelNotFound = "model_not_found"
        case pendingSteering = "pending_steering"
        case previousResponseNotFound = "previous_response_not_found"
        case requestTooLarge = "request_too_large"
        case responseNotFound = "response_not_found"
        case steeringNotSupported = "steering_not_supported"
        case steeringAcknowledgementTimeout = "steering_acknowledgement_timeout"
        case steeringConnectionRetired = "steering_connection_retired"
        case tooManyPendingSteers = "too_many_pending_steers"
        case upstreamError = "upstream_error"
        case websocketConnectionLimitReached = "websocket_connection_limit_reached"
        case websocketStreamLimitReached = "websocket_stream_limit_reached"
    }

    enum RequestField: String {
        case previousResponseID = "previous_response_id"
        case stream, background, conversation, generate, prewarm
        case promptCacheOptions = "prompt_cache_options"
        case streamID = "stream_id"
    }

    enum EventField: String {
        case responseID = "response_id"
        case sequenceNumber = "sequence_number"
    }

    /// Steering control payloads are not part of the generated event projection.
    enum ControlField: String {
        case steer
    }

    enum SteeringField: String {
        case id
        case previousResponseID = "previous_response_id"
    }

    enum Event: String {
        case create = "response.create"
        case steer = "response.steer"
        case steerSubmitted = "response.steer.submitted"
        case steerAccepted = "response.steer.accepted"
        case steerPending = "response.steer.pending"
        case steerFailed = "response.steer.failed"
    }

    enum Kind: String {
        case compactionTrigger = "compaction_trigger"
    }

    enum ErrorType: String {
        case invalidRequestError = "invalid_request_error"
        case rateLimitError = "rate_limit_error"
        case serverError = "server_error"
    }
}
