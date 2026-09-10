import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OTLP acknowledgements")
struct OTLPExportResponseTests {
    @Test("The measured receiver compatibility is explicit and narrow")
    func emptyReplies() {
        #expect(parse(200, "", type: nil) == .accepted)
        #expect(parse(204, "", signal: .logs, type: nil) == .accepted)
        #expect(parse(204, "") == .permanent(.invalidResponse))
        #expect(parse(201, "{}") == .permanent(.httpStatus(201)))
        #expect(parse(204, "{}", signal: .logs) == .permanent(.invalidResponse))
        #expect(parse(200, "{}", type: "text/html") == .permanent(.invalidResponse))
    }

    @Test("Success, partial rejection and warning envelopes never expose receiver text")
    func envelopes() {
        #expect(parse(200, "{}") == .accepted)
        #expect(parse(200, #"{"unknown":true,"partialSuccess":{}}"#) == .accepted)
        #expect(
            parse(200, #"{"partialSuccess":{"rejectedDataPoints":"12","errorMessage":"PRIVATE"}}"#)
                == .partial(rejected: 12))
        #expect(parse(200, #"{"partialSuccess":{"rejectedLogRecords":3}}"#, signal: .logs) == .partial(rejected: 3))
        #expect(parse(200, #"{"partialSuccess":{"rejectedDataPoints":0,"errorMessage":"PRIVATE"}}"#) == .warning)
        #expect(parse(200, #"{"partialSuccess":{"rejectedDataPoints":"0","errorMessage":""}}"#) == .accepted)
        #expect(parse(200, "{}", type: "Application/JSON; charset=utf-8") == .accepted)
    }

    @Test("Invalid acknowledgements are permanent protocol errors")
    func invalidEnvelopes() {
        for body in [
            "invalid", "[]", "null", #"{"partialSuccess":false}"#,
            #"{"partialSuccess":{"rejectedDataPoints":-1}}"#,
            #"{"partialSuccess":{"rejectedDataPoints":true}}"#,
            #"{"partialSuccess":{"rejectedDataPoints":1.5}}"#,
            #"{"partialSuccess":{"rejectedDataPoints":"9223372036854775808"}}"#,
            #"{"partialSuccess":{"errorMessage":42}}"#,
        ] {
            #expect(parse(200, body) == .permanent(.invalidResponse))
        }
        #expect(parse(200, String(repeating: " ", count: 1_048_577)) == .permanent(.responseTooLarge))
    }

    @Test("Only protocol-defined HTTP failures can be retried")
    func statusClassification() {
        for status in [429, 502, 503, 504] {
            #expect(parse(status, "PRIVATE") == .retryable(.httpStatus(status)))
        }
        for status in [301, 307, 400, 401, 403, 404, 413, 500] {
            #expect(parse(status, "PRIVATE") == .permanent(.httpStatus(status)))
        }
    }

    private func parse(
        _ status: Int,
        _ body: String,
        signal: MonitoringSignal = .metrics,
        type: String? = "application/json"
    ) -> OTLPExportResult {
        OTLPExportResponse.parse(
            .init(status: status, contentType: type, retryAfter: nil, body: Data(body.utf8)), signal: signal
        )
    }
}
