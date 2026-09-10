import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("MCP makes disabled search and absent credentials actionable tool errors")
    func webSearchMCPUnavailable() async throws {
        for provider in [WebSearchProvider.disabled, .firecrawl] {
            let configured = try makeWebSearchFixture(provider: provider)
            let fixture = GatewayFixture(
                snapshot: configured.snapshot, state: configured.state, secrets: MemorySecretStore())
            let transport = RecordingGatewayTransport(responses: [])
            let app = makeApplication(fixture: fixture, transport: transport)
            try await app.test(.router) { client in
                let result = try await client.execute(
                    uri: "/api/mcp",
                    method: .post,
                    headers: webSearchMCPHeaders,
                    body: ByteBuffer(string: webSearchMCPCall)
                )
                #expect(result.status == .ok)
                let payload = try mcpToolPayload(data(result.body))
                #expect(payload["isError"] as? Bool == true)
                let expected =
                    provider == .disabled
                    ? "Web search is disabled. Enable a search provider in LittleSwitch Settings."
                    : "Web search credential is missing. Configure it in LittleSwitch Settings."
                #expect(try mcpToolText(payload) == expected)
                #expect(await transport.requests.isEmpty)
            }
        }
    }

    @Test("MCP reports provider failure without leaking private upstream details")
    func webSearchMCPProviderFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .unauthorized, body: #"{"private":"must-not-escape"}"#)
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/mcp",
                method: .post,
                headers: webSearchMCPHeaders,
                body: ByteBuffer(string: webSearchMCPCall)
            )
            #expect(result.status == .ok)
            let payload = try mcpToolPayload(data(result.body))
            #expect(payload["isError"] as? Bool == true)
            #expect(
                try mcpToolText(payload)
                    == "Web search provider failed. Check the search provider in LittleSwitch Settings.")
            let text = try #require(String(data: data(result.body), encoding: .utf8))
            #expect(!text.contains("must-not-escape"))
        }
    }

    @Test("MCP converts SecretStore failures to a private tool error")
    func webSearchMCPCredentialAccessFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: ThrowingGatewaySecretStore(),
            requiredAuthorityPort: nil
        )
        let result = try await responder.routeResponse(webSearchMCPRequest(), eventID: UUID())
        let payload = try mcpToolPayload(await responseBodyData(result.body))
        #expect(payload["isError"] as? Bool == true)
        #expect(try mcpToolText(payload) == "Web search is unavailable. Check LittleSwitch Settings.")
        #expect(await transport.requests.isEmpty)
    }

    @Test("MCP preserves cancellation while reading requests and searching")
    func webSearchMCPCancellation() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = SteppingGatewayTransport(steps: [.cancellation])
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil
        )
        let bodyRequest = webSearchMCPRequest(body: RequestBody(asyncSequence: CancellingGatewayBodySequence()))
        await #expect(throws: CancellationError.self) {
            _ = try await responder.routeResponse(bodyRequest, eventID: UUID())
        }
        #expect(await transport.requests.isEmpty)
        await #expect(throws: CancellationError.self) {
            _ = try await responder.routeResponse(webSearchMCPRequest(), eventID: UUID())
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("MCP body stream failure stays a transport error without provider work")
    func webSearchMCPBodyFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil
        )
        let result = try await responder.routeResponse(
            webSearchMCPRequest(body: RequestBody(asyncSequence: FailingGatewayBodySequence())), eventID: UUID()
        )
        #expect(result.status == .badRequest)
        #expect(
            try mcpJSONEqual(
                await responseBodyData(result.body),
                #"{"jsonrpc":"2.0","error":{"code":-32600,"message":"Could not read request body"}}"#))
        #expect(await transport.requests.isEmpty)
    }
}

func webSearchMCPRequest(body: RequestBody? = nil) -> Request {
    Request(
        head: HTTPRequest(
            method: .post, scheme: "http", authority: "localhost", path: "/api/mcp", headerFields: webSearchMCPHeaders),
        body: body ?? RequestBody(buffer: ByteBuffer(string: webSearchMCPCall))
    )
}

func mcpToolPayload(_ data: Data) throws -> [String: Any] {
    let object = try anthropicObject(data)
    return try #require(object["result"] as? [String: Any])
}

func mcpToolText(_ payload: [String: Any]) throws -> String {
    let content = try #require(payload["content"] as? [[String: Any]])
    return try #require(content.first?["text"] as? String)
}
