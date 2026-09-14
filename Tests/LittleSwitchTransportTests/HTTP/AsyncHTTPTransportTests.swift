import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite("AsyncHTTP transport")
struct AsyncHTTPTransportTests {
    @Test("The traffic-grade window allows ten minutes for long model and image requests")
    func trafficWindowDefault() {
        #expect(AsyncHTTPTransport.defaultTimeout == .seconds(600))
    }
}
