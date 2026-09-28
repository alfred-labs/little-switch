import Foundation
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

struct WebSocketHeaderValidationTests {
    @Test(arguments: [
        ("", "value"), ("Bad Name", "value"), ("X-Ä", "value"), ("Name:", "value"),
        ("X-Test", "one\r\nInjected: two"), ("X-Test", "zero\0byte"), ("X-Test", "delete\u{7F}"),
    ])
    func rejectsMalformedHTTPFieldsBeforeConnecting(name: String, value: String) throws {
        let url = try #require(URL(string: "wss://example.test/responses"))
        #expect {
            try UpstreamWebSocketRequest(url: url, headers: HTTPHeaders([(name, value)]))
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .invalidRequest
        }
    }

    @Test func preservesLegalTokenNamesAndFieldValues() throws {
        let url = try #require(URL(string: "wss://example.test/responses"))
        let headers = HTTPHeaders([("X-!#$%&'*+-.^_`|~", "tab\tand café"), ("Origin", "https://example.test")])
        let request = try UpstreamWebSocketRequest(url: url, headers: headers)
        #expect(request.headers == headers)
    }
}
