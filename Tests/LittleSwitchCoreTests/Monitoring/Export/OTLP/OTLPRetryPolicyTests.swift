import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OTLP retry policy")
struct OTLPRetryPolicyTests {
    @Test("Retry-After is respected beyond the normal backoff cap")
    func retryAfter() {
        let date = Date(timeIntervalSince1970: 1_000)
        #expect(OTLPRetryPolicy.delay(attempt: 0, retryAfter: "120", now: date, jitter: 0.5) == 120)
        #expect(
            OTLPRetryPolicy.delay(attempt: 0, retryAfter: "Thu, 01 Jan 1970 00:18:20 GMT", now: date, jitter: 1) == 100)
        #expect(
            OTLPRetryPolicy.delay(attempt: 0, retryAfter: "Thu, 01 Jan 1970 00:00:00 GMT", now: date, jitter: 1) == 0)
        #expect(OTLPRetryPolicy.delay(attempt: 0, retryAfter: "0", now: date, jitter: 1) == 0)
    }

    @Test("Backoff is bounded and malformed headers do not cause a busy retry")
    func exponentialBackoff() {
        for header in [nil, "invalid", "-1", "1.5", "NaN", "inf"] {
            #expect(OTLPRetryPolicy.delay(attempt: 0, retryAfter: header, jitter: 0.5) == 0.5)
        }
        #expect(OTLPRetryPolicy.delay(attempt: 2, retryAfter: nil, jitter: 1.5) == 6)
        #expect(OTLPRetryPolicy.delay(attempt: 100, retryAfter: nil, jitter: 1.5) == 30)
        #expect(OTLPRetryPolicy.delay(attempt: -1, retryAfter: nil, jitter: 0) == 0.5)
    }

    @Test("TLS and cancellation differ from transient network failures")
    func transportErrors() {
        #expect(OTLPExportResponse.classify(CancellationError()) == .cancelled)
        #expect(OTLPExportResponse.classify(URLError(.cancelled)) == .cancelled)
        for code in [URLError.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet] {
            #expect(OTLPExportResponse.classify(URLError(code)) == .retryable(.network))
        }
        for code in [URLError.serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed] {
            #expect(OTLPExportResponse.classify(URLError(code)) == .permanent(.tls))
        }
        #expect(OTLPExportResponse.classify(URLError(.badURL)) == .permanent(.invalidEndpoint))
        #expect(
            OTLPExportResponse.classify(OTLPHTTPTransport.Failure.responseTooLarge) == .permanent(.responseTooLarge))
    }
}
