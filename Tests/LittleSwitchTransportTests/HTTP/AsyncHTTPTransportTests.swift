import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite("AsyncHTTP transport")
struct AsyncHTTPTransportTests {
    @Test("The traffic-grade window defaults to 120 seconds")
    func trafficWindowDefault() {
        #expect(AsyncHTTPTransport.defaultTimeout == .seconds(120))
    }
}
