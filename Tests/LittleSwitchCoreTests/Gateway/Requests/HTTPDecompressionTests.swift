import AsyncHTTPClient
import HTTPTypes
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("HTTP decompression")
struct HTTPDecompressionTests {

    @Test("Forwarded headers describe the decompressed response body")
    func forwardedHeaders() throws {
        let fields = gatewayResponseHeaders([
            "content-encoding": "gzip",
            "content-length": "123",
            "content-type": "application/json",
            "x-upstream": "yes",
        ])
        let upstream = try #require(HTTPField.Name("x-upstream"))

        #expect(fields[.contentEncoding] == nil)
        #expect(fields[.contentLength] == nil)
        #expect(fields[.contentType] == "application/json")
        #expect(fields[upstream] == "yes")
    }
}
