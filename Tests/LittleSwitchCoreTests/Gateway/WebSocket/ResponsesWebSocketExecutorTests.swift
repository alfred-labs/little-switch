import Foundation
import HTTPTypes
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses WebSocket execution")
struct ResponsesWebSocketExecutorTests {
    @Test("Each turn preserves client correlation and authentication but removes handshake framing")
    func requestHeaders() throws {
        let fixture = try GatewayTests().makeFixture()
        let betaHeader = try #require(HTTPField.Name("OpenAI-Beta"))
        let metadataHeader = try #require(HTTPField.Name("x-codex-turn-metadata"))
        let executor = makeExecutor(
            fixture: fixture,
            headers: [
                .authorization: "Bearer synthetic-client", .connection: "Upgrade", .upgrade: "websocket",
                .secWebSocketKey: "synthetic-key", .secWebSocketVersion: "13", .secWebSocketProtocol: "test",
                .contentLength: "0", .contentEncoding: "zstd", .transferEncoding: "chunked",
                betaHeader: "responses_websockets=2026-02-06",
                metadataHeader: "synthetic-turn",
            ])
        let request = executor.httpRequest(body: Data("{}".utf8))
        #expect(request.method == .post)
        #expect(request.uri.path == "/v1/responses")
        #expect(
            request.headers == [
                .authorization: "Bearer synthetic-client",
                betaHeader: "responses_websockets=2026-02-06",
                metadataHeader: "synthetic-turn",
                .contentType: "application/json", .accept: "text/event-stream",
            ])
    }

    @Test(
        "Managed and native warmups create a chainable response without an upstream request", arguments: [false, true])
    func warmup(native: Bool) async throws {
        let fixture = try GatewayTests().makeFixture()
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let model = native ? "gpt-6" : CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let transport = RecordingGatewayTransport(responses: [])
        let executor = makeExecutor(fixture: fixture, transport: transport)
        let events = WebSocketEventRecorder()
        let result = try await executor.execute(warmupTurn(["model": .string(model), "input": []])) {
            await events.append($0)
        }
        #expect(result.responseID?.hasPrefix("resp_ls_") == true)
        #expect(result.output == Data("[]".utf8))
        #expect(
            try await events.values().map { $0["type"] } == [
                .string("response.created"), .string("response.in_progress"),
            ])
        #expect(try JSONValue.parse(result.terminal).object?["response"]?.object?["status"] == .string("completed"))
        #expect(await transport.requests.isEmpty)
    }

    @Test("Warmup rejects missing models, unknown routes and native sentinel credentials", arguments: [0, 1, 2])
    func invalidWarmup(caseIndex: Int) async throws {
        let fixture = try GatewayTests().makeFixture()
        let executor = makeExecutor(
            fixture: fixture,
            headers: caseIndex == 2 ? [.authorization: "Bearer \(CodexNativePassthrough.sentinelAPIKey)"] : [:])
        let body: JSONObject = caseIndex == 0 ? [:] : ["model": .string(caseIndex == 1 ? "unknown/model" : "gpt-6")]
        do {
            _ = try await executor.execute(warmupTurn(body)) { _ in Issue.record("Invalid warmup emitted events") }
            Issue.record("Expected a warmup validation failure")
        } catch let failure as ResponsesWebSocketFailure {
            #expect(failure.status == (caseIndex == 2 ? 401 : 400))
            #expect(failure.streamID == "warm")
        }
    }

    @Test("Invalid owned history in a warmup is a client error")
    func invalidWarmupHistory() async throws {
        let fixture = try GatewayTests().makeFixture()
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let model = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let body: JSONObject = [
            "model": .string(model),
            "input": [
                [
                    "type": "reasoning", "encrypted_content": "{\"type\":\"little_switch_reasoning\",\"version\":2}",
                ]
            ],
        ]
        do {
            _ = try await makeExecutor(fixture: fixture).execute(warmupTurn(body)) { _ in }
            Issue.record("Expected invalid owned history to fail warmup")
        } catch let failure as ResponsesWebSocketFailure {
            #expect(failure.status == 400)
        }
    }

    private func makeExecutor(
        fixture: GatewayFixture,
        headers: HTTPFields = [:],
        transport: RecordingGatewayTransport = RecordingGatewayTransport(responses: [])
    ) -> ResponsesWebSocketExecutor {
        .init(
            responder: GatewayResponder(
                state: fixture.state, transport: transport, secretStore: fixture.secrets, requiredAuthorityPort: nil),
            request: webSocketHTTPRequest(headers: headers),
            limits: .init())
    }

    private func warmupTurn(_ fields: JSONObject) throws -> ResponsesWebSocketTurn {
        .init(
            id: UUID(),
            streamID: "warm",
            body: try JSONValue.object(fields).serializedData(),
            generate: false,
            previousResponseID: nil,
            replacesHistory: false)
    }
}
