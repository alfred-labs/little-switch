import Foundation

package struct OTLPHTTPResponse: Sendable {
    package let status: Int
    package let contentType: String?
    package let retryAfter: String?
    package let body: Data
}

package protocol OTLPTransporting: Sendable {
    func send(to endpoint: URL, body: Data, bearer: String?) async throws -> OTLPHTTPResponse
    func shutdown() async
}

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

package enum OTLPExportResult: Equatable, Sendable {
    case accepted
    case partial(rejected: UInt64)
    case warning
    case retryable(OTLPExportFailure)
    case permanent(OTLPExportFailure)
    case cancelled
}
