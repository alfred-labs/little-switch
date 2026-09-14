import Foundation
import LittleSwitchCommon

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

package enum OTLPExportResult: Equatable, Sendable {
    case accepted
    case partial(rejected: UInt64)
    case warning
    case retryable(OTLPExportFailure)
    case permanent(OTLPExportFailure)
    case cancelled
}
