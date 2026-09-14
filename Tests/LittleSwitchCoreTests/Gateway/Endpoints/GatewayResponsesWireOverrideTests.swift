import AsyncHTTPClient
import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    /// A chat-completions-only provider on a custom base URL: no z.ai preset,
    /// so the first request probes native /v1/responses before learning.
    private func makeChatOnlyFixture(
        responsesWireOverride: ProviderResponsesWireOverride? = nil,
        webSearch: Bool = true
    ) throws -> (GatewayFixture, ModelMapping) {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "ChatOnly",
            baseURL: "https://example.com/api",
            authMode: .bearer,
            models: [
                DiscoveredModel(id: "chat-model", maxTokens: 8_192, detectedContextWindow: nil)
            ],
            responsesWireOverride: responsesWireOverride
        )
        let mapping = ModelMapping(providerID: providerID, modelID: "chat-model")
        let webSearchConfiguration =
            webSearch
            ? WebSearchConfiguration(provider: .firecrawl, resultsLimit: 10, maximumUses: 3)
            : WebSearchConfiguration.disabled
        let snapshot = RoutingSnapshot(
            generation: 1,
            providers: [provider],
            mappings: ["claude-opus-5": mapping],
            codex: CodexConfiguration(defaultModel: mapping),
            webSearch: webSearchConfiguration
        )
        let secrets = MemorySecretStore()
        try secrets.write("selected-secret", providerID: providerID)
        if webSearch {
            try secrets.write("firecrawl-secret", account: .webSearch(.firecrawl))
        }
        let state = GatewayState(snapshot: snapshot)
        return (
            GatewayFixture(snapshot: snapshot, state: state, secrets: secrets),
            mapping
        )
    }

    private func bufferedSearchRequest(slug: String) -> String {
        #"""
        {
          "model": "\#(slug)",
          "input": "hello",
          "stream": false,
          "tools": [{"type": "web_search"}]
        }
        """#
    }

    private func chatFinalResponse() -> String {
        responsesModelResponse(
            id: "chatcmpl_final",
            output: [
                [
                    "id": "msg_final",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": "via adapter", "annotations": [], "logprobs": []]
                    ],
                ]
            ]
        )
    }

    @Test("A web-search native 404 falls back to the adapter within the same request")
    func webSearch404FallsBackToAdapter() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: #"{"detail":"Not Found"}"#),
            response(status: .ok, body: chatFinalResponse()),
        ])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(fixture: fixture, transport: transport, trafficRecorder: recorder)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: bufferedSearchRequest(slug: slug))
            )
            #expect(result.status == .ok)
            let object = try responsesGatewayObject(Data(result.body.readableBytesView))
            let output = try #require(object["output"] as? [[String: Any]])
            #expect(
                output.compactMap { $0["type"] as? String } == ["message"]
            )
        }

        let urls = await transport.requests.map(\.url)
        #expect(
            urls == [
                "https://example.com/api/v1/responses",
                "https://example.com/api/v1/chat/completions",
            ]
        )
        // The retry records under its own attempt: the traffic log keeps the
        // failed native exchange and the adapter exchange side by side
        // instead of the retry overwriting the 404 it replaced.
        let event = try #require(recorder.events.first)
        #expect(event.upstreamExchanges.count == 2)
        #expect(event.upstreamExchanges[0].responseStatus == 404)
        #expect(event.upstreamExchanges[0].request?.url.hasSuffix("/v1/responses") == true)
        #expect(event.upstreamExchanges[1].responseStatus == 200)
        #expect(
            event.upstreamExchanges[1].request?.url.hasSuffix("/v1/chat/completions") == true
        )
        #expect(
            event.upstreamExchanges[1].response.body
                != Data(#"{"detail":"Not Found"}"#.utf8)
        )
        #expect(
            await fixture.state.responsesCapabilityVerdicts()[fixture.snapshot.providers[0].id]
                == false
        )
    }

    @Test("A 404 on the adapter's own route relearns the native wire")
    func chatRouteAbsenceRelearnsNative() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture()
        let providerID = fixture.snapshot.providers[0].id
        await fixture.state.responsesCapabilities.record(
            providerID: providerID,
            supportsNative: false
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: #"{"detail":"Not Found"}"#)
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: bufferedSearchRequest(slug: slug))
            )
            // The 404 relays honestly this once; the verdict relearned is
            // the point — the next request takes the native wire.
            #expect(result.status == .notFound)
        }

        let urls = await transport.requests.map(\.url)
        #expect(urls == ["https://example.com/api/v1/chat/completions"])
        #expect(
            await fixture.state.responsesCapabilityVerdicts()[providerID] == true
        )
    }

    @Test("An adapter success never re-arms the native probe")
    func adapterSuccessDoesNotPoisonTheLedger() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: #"{"detail":"Not Found"}"#),
            response(status: .ok, body: chatFinalResponse()),
            response(status: .ok, body: chatFinalResponse()),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let headers: HTTPFields = [
            .contentType: "application/json",
            .authorization: "Bearer incoming",
        ]
        let body = ByteBuffer(string: bufferedSearchRequest(slug: slug))

        try await app.test(.router) { client in
            let first = try await client.execute(
                uri: "/v1/responses", method: .post, headers: headers, body: body
            )
            #expect(first.status == .ok)
            let second = try await client.execute(
                uri: "/v1/responses", method: .post, headers: headers, body: body
            )
            #expect(second.status == .ok)
        }

        // One native probe, then the adapter for every later request — the
        // exact oscillation the poisoning produced before.
        let urls = await transport.requests.map(\.url)
        #expect(
            urls == [
                "https://example.com/api/v1/responses",
                "https://example.com/api/v1/chat/completions",
                "https://example.com/api/v1/chat/completions",
            ]
        )
    }

    @Test("A streaming web-search native 404 recovers on the adapter mid-request")
    func liveWebSearch404FallsBackToAdapter() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture()
        let chatSSE = try #require(
            String(data: liveZAIFinalChunks()[0], encoding: .utf8)
        )
        let stream = AsyncStream<ByteBuffer> { continuation in
            continuation.yield(ByteBuffer(string: chatSSE))
            continuation.finish()
        }
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: #"{"detail":"Not Found"}"#),
            HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                body: .stream(stream)
            ),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let requestBody =
            #"""
            {
              "model": "\#(slug)",
              "input": "latest Swift",
              "stream": true,
              "tools": [{"type": "web_search"}]
            }
            """#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: requestBody)
            )
            #expect(result.status == .ok)
            #expect(result.headers[.contentType] == "text/event-stream")
            let sse = try #require(
                String(data: Data(result.body.readableBytesView), encoding: .utf8)
            )
            #expect(sse.contains("event: response.completed"))
            #expect(sse.contains("FIRST SECOND"))
        }

        let urls = await transport.requests.map(\.url)
        #expect(
            urls == [
                "https://example.com/api/v1/responses",
                "https://example.com/api/v1/chat/completions",
            ]
        )
    }

    @Test("A provider pinned to chat completions never probes /v1/responses")
    func forcedChatSkipsNativeEntirely() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture(
            responsesWireOverride: .chatCompletions
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: chatFinalResponse())
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: bufferedSearchRequest(slug: slug))
            )
            #expect(result.status == .ok)
        }

        let urls = await transport.requests.map(\.url)
        #expect(urls == ["https://example.com/api/v1/chat/completions"])
    }

    @Test("A provider pinned to native relays the 404 instead of adapting")
    func forcedNativeRelaysFailures() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture(
            responsesWireOverride: .native
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: #"{"detail":"Not Found"}"#)
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: bufferedSearchRequest(slug: slug))
            )
            #expect(result.status == .notFound)
            let body = try #require(
                String(data: Data(result.body.readableBytesView), encoding: .utf8)
            )
            #expect(body == #"{"detail":"Not Found"}"#)
        }

        let urls = await transport.requests.map(\.url)
        #expect(urls == ["https://example.com/api/v1/responses"])
    }

    @Test("A transparent adapter 404 also relearns the native wire")
    func transparentChatRouteAbsenceRelearnsNative() async throws {
        let base = try makeFixture()
        let providerID = base.snapshot.providers[0].id
        // The save-time probe already learned the provider has no native
        // route (z.ai answers 404 there), so dispatch starts on the adapter.
        await base.state.responsesCapabilities.record(
            providerID: providerID,
            supportsNative: false
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .notFound, body: #"{"detail":"Not Found"}"#)
        ])
        let app = makeApplication(fixture: base, transport: transport)
        let mapping = try #require(
            base.snapshot.codex.resolvedDefaultModel(in: base.snapshot.providers)
        )
        let slug = CodexCatalog.slug(for: mapping, in: base.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: bufferedSearchRequest(slug: slug))
            )
            #expect(result.status == .notFound)
        }

        let urls = await transport.requests.map(\.url)
        #expect(urls == ["https://api.z.ai/api/coding/paas/v4/chat/completions"])
        #expect(
            await base.state.responsesCapabilityVerdicts()[providerID] == true
        )
    }

    @Test("A pinned wire outranks the learned verdict and the URL heuristic")
    func overrideOutranksLedgerAndHeuristic() async throws {
        let base = try makeFixture()
        let pinnedChat = Provider(
            id: base.snapshot.providers[0].id,
            name: "z.ai",
            baseURL: "https://api.z.ai/api/anthropic",
            authMode: .bearer,
            responsesWireOverride: .chatCompletions
        )
        let pinnedNative = Provider(
            id: UUID(),
            name: "ChatOnly",
            baseURL: "https://example.com/api",
            authMode: .bearer,
            responsesWireOverride: .native
        )
        let ledger = ResponsesCapabilityLedger()
        let state = GatewayState(
            snapshot: base.snapshot,
            routingMutationGuard: GatewayRoutingMutationGuard(),
            responsesCapabilities: ledger
        )
        let responder = GatewayResponder(
            state: state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: base.secrets,
            requiredAuthorityPort: nil
        )

        await ledger.record(providerID: pinnedChat.id, supportsNative: true)
        #expect(await responder.resolvesChatCompletionsAdapter(pinnedChat) == true)

        await ledger.record(providerID: pinnedNative.id, supportsNative: false)
        #expect(await responder.resolvesChatCompletionsAdapter(pinnedNative) == false)
    }
}

extension GatewayTests {
    @Test("A chat-completions relay that fails upstream reports 502")
    func chatRelayFailureReportsBadGateway() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture(
            responsesWireOverride: .chatCompletions,
            webSearch: false
        )
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"keep"}"#)
            )
            #expect(result.status == .badGateway)
            let object = try responsesGatewayObject(Data(result.body.readableBytesView))
            let error = try #require(object["error"] as? [String: Any])
            #expect(error["message"] as? String == "Provider request failed")
        }
    }
}

extension GatewayTests {
    @Test("A cancelled chat-completions relay rethrows the cancellation")
    func chatRelayCancellationRethrows() async throws {
        let (fixture, mapping) = try makeChatOnlyFixture(
            responsesWireOverride: .chatCompletions,
            webSearch: false
        )
        let app = makeApplication(fixture: fixture, transport: CancellingGatewayTransport())
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer incoming",
                ],
                body: ByteBuffer(string: #"{"model":"\\#(slug)","input":"keep"}"#)
            )
            // The cancellation escapes the handler instead of becoming a
            // provider-shaped 502; the test server surfaces it as 400.
            #expect(result.status == .badRequest)
        }
    }
}
