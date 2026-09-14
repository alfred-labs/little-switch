import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway search configuration snapshots")
struct GatewaySearchConfigurationTests {
    @Test("Routing updates capture, preserve, and replace web search settings")
    func routingSnapshot() async {
        let state = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 4,
                providers: [],
                mappings: [:],
                webSearch: .firecrawlCloud
            )
        )
        #expect(await state.capture().webSearch == .firecrawlCloud)

        let preserved = await state.replace(providers: [], mappings: [:])
        #expect(preserved.generation == 5)
        #expect(preserved.webSearch == .firecrawlCloud)

        let replaced = await state.replace(
            providers: [],
            mappings: [:],
            webSearch: .disabled
        )
        #expect(replaced.generation == 6)
        #expect(replaced.webSearch == .disabled)
    }
}
