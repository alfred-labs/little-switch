import AsyncHTTPClient
import Foundation
import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite("Transport defaults")
struct UpstreamTransportTests {
    @Test("Default transport configuration enables proxy-free bounded decompression")
    func transportDefaults() {
        let configuration = AsyncHTTPTransport.httpClientConfiguration()
        #expect(configuration.proxy == nil)
        guard case .enabled = configuration.decompression else {
            Issue.record("Expected bounded automatic response decompression")
            return
        }
        // The exact ratio limit (25) is set in httpClientConfiguration; its
        // internal representation is a NIO type without public accessors.
        // The live decompression test in HTTPTransportDecompressionTests
        // verifies the behavior end-to-end over a real loopback connection.
    }
}
