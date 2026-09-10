public enum MonitoringMetricName: String, CaseIterable, Sendable {
    case requests = "littleswitch.gateway.requests"
    case tokens = "littleswitch.gateway.tokens"
    case estimatedInputTokens = "littleswitch.gateway.estimated_input_tokens"
    case duration = "littleswitch.gateway.request.duration"
    case inFlight = "littleswitch.gateway.requests_in_flight"
    case waiting = "littleswitch.provider.requests_waiting"
    case admissionRejections = "littleswitch.gateway.admission_rejections"
    case admissionTimeouts = "littleswitch.gateway.admission_timeouts"
    case webSearches = "littleswitch.gateway.web_searches"
    case dropped = "littleswitch.monitoring.dropped"
    case test = "littleswitch.monitoring.test"

    public var prometheusName: String {
        switch self {
        case .requests: "littleswitch_gateway_requests_total"
        case .tokens: "littleswitch_gateway_tokens_total"
        case .estimatedInputTokens: "littleswitch_gateway_estimated_input_tokens_total"
        case .duration: "littleswitch_gateway_request_duration_seconds"
        case .inFlight: "littleswitch_gateway_requests_in_flight"
        case .waiting: "littleswitch_provider_requests_waiting"
        case .admissionRejections: "littleswitch_gateway_admission_rejections_total"
        case .admissionTimeouts: "littleswitch_gateway_admission_timeouts_total"
        case .webSearches: "littleswitch_gateway_web_searches_total"
        case .dropped: "littleswitch_monitoring_dropped_total"
        case .test: "littleswitch_monitoring_test"
        }
    }

    public var unit: String { self == .duration ? "s" : "" }

    public var type: String {
        switch self {
        case .duration: "histogram"
        case .inFlight, .waiting, .test: "gauge"
        default: "counter"
        }
    }

    public var help: String {
        switch self {
        case .requests: "Completed gateway requests."
        case .tokens: "Tokens reported by providers."
        case .estimatedInputTokens: "Locally estimated input tokens."
        case .duration: "Gateway request duration including the complete response stream, in seconds."
        case .inFlight: "Gateway requests currently in flight."
        case .waiting: "Requests waiting for provider admission."
        case .admissionRejections: "Requests rejected during provider admission."
        case .admissionTimeouts: "Requests that timed out waiting for provider admission."
        case .webSearches: "Executed web searches."
        case .dropped: "Monitoring observations lost by signal and reason."
        case .test: "Synthetic monitoring export test marker."
        }
    }
}
