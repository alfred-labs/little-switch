import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("MCP observes applied search changes without counting them as model requests")
    func webSearchMCPAppliedStateAndAccounting() async throws {
        let fixture = try makeWebSearchFixture(maximumUses: 1)
        try fixture.secrets.write(WebSearchProvider.exa.searchTestCredential, account: .webSearch(.exa))
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: gatewaySearchResponseBody(provider: .firecrawl)),
            response(status: .ok, body: gatewaySearchResponseBody(provider: .exa)),
        ])
        let recorder = TrafficTestRecorder()
        let store = MonitoringStore()
        let monitoring = GatewayMonitoring(store: store) { .init(exposeLogs: true) }
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder,
                monitoring: monitoring))
        let before = await store.snapshot(at: store.resource.startedAt)
        #expect(before.families.isEmpty)
        try await app.test(.router) { client in
            for provider in [WebSearchProvider.firecrawl, .exa, .disabled] {
                await fixture.state.replace(
                    providers: fixture.snapshot.providers,
                    mappings: fixture.snapshot.mappings,
                    webSearch: WebSearchConfiguration(provider: provider, resultsLimit: 10, maximumUses: 1)
                )
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(string: webSearchMCPCall)
                )
                #expect(result.status == .ok)
                let payload = try mcpToolPayload(data(result.body))
                #expect(payload["isError"] as? Bool == (provider == .disabled))
            }
        }
        #expect(await transport.requests.count == 2)
        #expect(recorder.events.flatMap(\.webSearches).map(\.provider) == ["firecrawl", "exa"])
        #expect(await fixture.state.sessionRequestCount == 0)
        let after = await store.snapshot(at: store.resource.startedAt)
        #expect(after.families.map(\.name) == [.webSearches])
        #expect(after.family(.webSearches)?.points.map(\.value) == [.counter(1), .counter(1)])
        #expect(try await store.logs().entries.isEmpty)
    }

    @Test("MCP accepts supported version headers and valid media type parameters")
    func webSearchMCPNegotiatedHeaders() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let versionHeader = try #require(HTTPField.Name("MCP-Protocol-Version"))
        try await app.test(.router) { client in
            for version in ["2025-06-18", "2025-11-25"] {
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: [
                        .contentType: "Application/JSON; charset=utf-8",
                        .accept: "application/json;q=0.8, text/event-stream;q=1",
                        versionHeader: version,
                    ],
                    body: ByteBuffer(string: #"{"jsonrpc":"2.0","id":"éclair","method":"ping"}"#)
                )
                #expect(result.status == .ok)
                #expect(try mcpJSONEqual(data(result.body), #"{"jsonrpc":"2.0","id":"éclair","result":{}}"#))
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}
