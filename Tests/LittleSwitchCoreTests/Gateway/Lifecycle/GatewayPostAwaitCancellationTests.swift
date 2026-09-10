import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Cancellation before the first Anthropic model turn propagates")
    func cancellationBeforeAnthropicModelTurn() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let task = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await responder.webSearchResponse(
                context: makePostAwaitWebSearchContext(fixture: fixture)
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Cancellation before the first Responses model turn propagates")
    func cancellationBeforeResponsesModelTurn() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let task = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await responder.responsesWebSearchResponse(
                context: makePostAwaitResponsesContext(fixture: fixture)
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Cancellation returned with a valid Anthropic final turn still propagates")
    func cancellationWithAnthropicFinalTurn() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = CancellingAnthropicFinalTurnTransport()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let task = Task {
            try await responder.webSearchResponse(
                context: makePostAwaitWebSearchContext(fixture: fixture)
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transport.requestCount == 1)
    }

    private func makePostAwaitWebSearchContext(
        fixture: GatewayFixture
    ) throws -> GatewayWebSearchContext {
        let target = try #require(fixture.snapshot.resolve(model: "claude-opus-5"))
        let candidate = try AnthropicWebSearch.prepare(
            body: Data(webSearchRequest(streaming: false, maximumUses: 1).utf8),
            targetModel: target.modelID,
            configuration: fixture.snapshot.webSearch
        )
        let prepared = try #require(candidate)
        return GatewayWebSearchContext(
            prepared: prepared,
            configuration: fixture.snapshot.webSearch,
            target: target,
            providerCredential: "selected-secret",
            incomingHeaders: [:],
            eventID: UUID()
        )
    }

    private func makePostAwaitResponsesContext(
        fixture: GatewayFixture
    ) throws -> GatewayResponsesWebSearchContext {
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let target = try #require(
            fixture.snapshot.resolveCodex(model: CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers))
        )
        let candidate = try OpenAIResponsesWebSearch.prepare(
            body: Data(
                responsesWebSearchRequest(slug: CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)).utf8
            ),
            targetModel: target.model.id,
            configuration: fixture.snapshot.webSearch
        )
        let prepared = try #require(candidate)
        return GatewayResponsesWebSearchContext(
            prepared: prepared,
            configuration: fixture.snapshot.webSearch,
            target: target,
            providerCredential: "selected-secret",
            searchCredential: "firecrawl-secret",
            incomingHeaders: [:],
            eventID: UUID(),
            needsChatCompletionsAdapter: true
        )
    }
}

private actor CancellingAnthropicFinalTurnTransport: UpstreamTransport {
    private(set) var requestCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        if let body = request.body {
            for try await _ in body {}
        }
        requestCount += 1
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return response(
            status: .ok,
            body: anthropicModelResponse(
                id: "msg_final",
                content: [["type": "text", "text": "Done"]],
                stopReason: "end_turn"
            )
        )
    }
}
