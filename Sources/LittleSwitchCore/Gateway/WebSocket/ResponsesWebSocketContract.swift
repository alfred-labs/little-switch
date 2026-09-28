/// WebSocket envelope and request options absent from the generated public
/// Responses projections. Projected provider fields use LittleSwitchWire keys.
enum ResponsesWebSocketContract {
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
