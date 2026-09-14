public enum OTLPExportFailure: Equatable, Sendable {
    case httpStatus(Int)
    case invalidResponse
    case responseTooLarge
    case network
    case tls
    case invalidEndpoint
    case credential

    public var message: String {
        switch self {
        case .httpStatus(let status): "The receiver returned HTTP \(status)."
        case .invalidResponse: "The receiver did not return a valid OTLP acknowledgement."
        case .responseTooLarge: "The receiver's response exceeded the size limit."
        case .network: "The receiver could not be reached."
        case .tls: "The receiver's secure connection could not be verified."
        case .invalidEndpoint: "Enter a valid receiver URL."
        case .credential: "The receiver's saved token is missing or invalid."
        }
    }
}
