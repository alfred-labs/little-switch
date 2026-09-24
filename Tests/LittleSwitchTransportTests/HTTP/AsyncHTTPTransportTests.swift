import AsyncHTTPClient
import Foundation
import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite("AsyncHTTP transport")
struct AsyncHTTPTransportTests {
    @Test("Authenticated native relays can refuse redirects before another request is sent")
    func refusesRedirectsWhenConfigured() async throws {
        let server = try LoopbackHTTPServer(
            statusCode: 302, contentType: "text/plain", body: Data(), location: "http://127.0.0.1:1/unwanted")
        try await server.start()
        let transport = AsyncHTTPTransport(followsRedirects: false)
        do {
            let port = try #require(server.port)
            let response = try await transport.execute(HTTPClientRequest(url: "http://127.0.0.1:\(port)/"))
            #expect(response.status == .found)
            try await transport.shutdown()
            await server.stop()
        } catch {
            try await transport.shutdown()
            await server.stop()
            throw error
        }
    }
    @Test("The traffic-grade window allows ten minutes for long model and image requests")
    func trafficWindowDefault() {
        #expect(AsyncHTTPTransport.defaultTimeout == .seconds(600))
    }
}
