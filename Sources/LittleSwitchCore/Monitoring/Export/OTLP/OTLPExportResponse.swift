import Foundation

package enum OTLPExportResponse {
    package static func parse(_ response: OTLPHTTPResponse, signal: MonitoringSignal) -> OTLPExportResult {
        guard response.body.count <= 1_048_576 else { return .permanent(.responseTooLarge) }
        if [429, 502, 503, 504].contains(response.status) {
            return .retryable(.httpStatus(response.status))
        }
        guard response.status == 200 || response.status == 204 else {
            return .permanent(.httpStatus(response.status))
        }
        let mediaType = response.contentType?
            .split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard mediaType == nil || mediaType == "application/json" else {
            return .permanent(.invalidResponse)
        }
        // Direct receiver proof: Prometheus 3.13.3 returns empty 200; Loki 3.7.7 returns empty 204.
        // No other status/body combination receives this compatibility exception.
        if response.status == 204 {
            return signal == .logs && response.body.isEmpty ? .accepted : .permanent(.invalidResponse)
        }
        if response.body.isEmpty { return .accepted }
        guard mediaType == "application/json" else { return .permanent(.invalidResponse) }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: response.body)
            guard let partial = envelope.partialSuccess else { return .accepted }
            let rejected = signal == .metrics ? partial.rejectedDataPoints : partial.rejectedLogRecords
            if let rejected, rejected.value > 0 { return .partial(rejected: UInt64(rejected.value)) }
            return partial.errorMessage?.isEmpty == false ? .warning : .accepted
        } catch {
            return .permanent(.invalidResponse)
        }
    }

    package static func classify(_ error: any Error) -> OTLPExportResult {
        if error is CancellationError { return .cancelled }
        if let failure = error as? OTLPHTTPTransport.Failure {
            switch failure {
            case .responseTooLarge: return .permanent(.responseTooLarge)
            case .invalidResponse: return .permanent(.invalidResponse)
            case .deadline: return .retryable(.network)
            case .invalidCredential: return .permanent(.credential)
            }
        }
        if error is MonitoringEndpoint.Error { return .permanent(.invalidEndpoint) }
        guard let error = error as? URLError else { return .permanent(.invalidResponse) }
        switch error.code {
        case .cancelled: return .cancelled
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
            .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable:
            return .retryable(.network)
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
            .clientCertificateRejected, .clientCertificateRequired:
            return .permanent(.tls)
        case .badURL, .unsupportedURL: return .permanent(.invalidEndpoint)
        default: return .permanent(.invalidResponse)
        }
    }

    private struct Envelope: Decodable {
        let partialSuccess: PartialSuccess?
    }

    private struct PartialSuccess: Decodable {
        let rejectedDataPoints: RejectedCount?
        let rejectedLogRecords: RejectedCount?
        let errorMessage: String?
    }

    private struct RejectedCount: Decodable {
        let value: Int64

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try? container.decode(String.self)
            let decimal = string?.utf8.allSatisfy { (48...57).contains($0) } == true
            if let string, decimal, let number = Int64(string) {
                value = number
            } else {
                value = try container.decode(Int64.self)
            }
            guard value >= 0 else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Negative rejection count")
            }
        }
    }
}
