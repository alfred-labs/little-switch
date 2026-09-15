public enum OTLPExportFailure: Equatable, Sendable {
    case httpStatus(Int)
    case invalidResponse
    case responseTooLarge
    case network
    case tls
    case invalidEndpoint
    case credential
}
