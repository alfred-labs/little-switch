import Foundation

package protocol MonitoringHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> MonitoringHTTPResponse
}

package struct MonitoringHTTPResponse: Sendable, Equatable {
    let status: Int
    let contentType: String?
    let body: Data
}

package typealias MonitoringSleep = @Sendable (Duration) async throws -> Void
package typealias MonitoringOutput = @Sendable (String) async -> Void
