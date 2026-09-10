import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Live Anthropic search streams each awaited phase without reading ahead")
    func liveAnthropicWebSearch() async throws {
        let fixture = try makeWebSearchFixture()
        let responseRace = GatewayLiveResponseRace()
        let firstBody = GatewayGatedBody(
            chunks: [try gatewayProviderSSE(searchedProviderTurnFrames())],
            responseRace: responseRace
        )
        let firecrawlGate = GatewayExecutionGate()
        let finalBody = GatewayGatedBody(
            chunks: try finalProviderTurnChunks(),
            gatedIndex: 1
        )
        let transport = GatewayLiveTransport(steps: [
            .response(gatewayStreamingResponse(firstBody)),
            .gated(
                firecrawlGate,
                response(
                    status: .ok,
                    body:
                        #"{"success":true,"data":{"web":[{"title":"Swift.org","url":"https://swift.org/","description":"Swift news"}]}}"#
                )
            ),
            .response(gatewayStreamingResponse(finalBody)),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let context = try gatewayLiveContext(fixture: fixture)

        let responseTask = Task {
            let response = try await responder.webSearchResponse(context: context)
            await responseRace.recordResponseReturned()
            return response
        }
        let firstEvent = await responseRace.waitForFirstEvent()
        #expect(firstEvent == .responseReturned)
        guard firstEvent == .responseReturned else {
            await firecrawlGate.release()
            await finalBody.release()
            _ = try? await responseTask.value
            return
        }

        let liveResponse = try await responseTask.value
        #expect(liveResponse.status == .ok)
        #expect(liveResponse.headers[.contentType] == "text/event-stream")
        #expect(liveResponse.body.contentLength == nil)
        #expect(await firstBody.readCount == 0)
        let initialRequests = await transport.requests
        #expect(initialRequests.count == 1)
        #expect(try anthropicObject(initialRequests[0].body)["stream"] as? Bool == true)

        let writerProbe = GatewayLiveWriterProbe(blockingMarker: #""text":"FIRST""#)
        let responseBody = liveResponse.body
        let bodyTask = Task {
            try await responseBody.write(GatewayLiveResponseWriter(probe: writerProbe))
        }

        try await firecrawlGate.waitUntilEntered()
        let beforeSearch = await writerProbe.string
        #expect(beforeSearch.contains(#""type":"server_tool_use""#))
        #expect(beforeSearch.contains("latest Swift"))
        #expect(!beforeSearch.contains("web_search_tool_result"))
        await firecrawlGate.release()

        await writerProbe.waitUntilContains(#""type":"web_search_tool_result""#)
        let afterSearch = await writerProbe.string
        #expect(afterSearch.contains(#""type":"web_search_tool_result""#))
        #expect(afterSearch.contains("https://swift.org/"))
        #expect(afterSearch.contains(#""caller":{"type":"direct"}"#))

        await writerProbe.waitUntilContains(#""text":"FIRST""#)
        #expect(await finalBody.readCount == 1)
        await writerProbe.releaseBlockedWrite()
        await finalBody.waitForReadCount(2)
        #expect((await writerProbe.string).contains(#""text":"FIRST""#))
        await finalBody.release()
        try await bodyTask.value

        let publicStream = await writerProbe.string
        #expect(publicStream.contains(#""text":"SECOND""#))
        #expect(publicStream.contains(#""web_search_requests":1"#))
        #expect(!publicStream.contains(#""type":"tool_use","id":"provider_search""#))
        #expect(!publicStream.contains(#""name":"weather""#))
        #expect(publicStream.components(separatedBy: "event: message_start\n").count - 1 == 1)
        #expect(publicStream.components(separatedBy: "event: message_stop\n").count - 1 == 1)
        #expect(await writerProbe.finished)

        let requests = await transport.requests
        try #require(requests.count == 3)
        #expect(try anthropicObject(requests[2].body)["stream"] as? Bool == true)
        #expect(requests.map(\.url).filter { $0.contains("firecrawl") }.count == 1)
        let firecrawl = try anthropicObject(requests[1].body)
        #expect(firecrawl["includeDomains"] as? [String] == ["swift.org"])
        #expect(firecrawl["location"] as? String == "Paris, Ile-de-France")
        #expect(firecrawl["country"] as? String == "FR")
    }

    @Test("Live Anthropic search accepts bounded provider JSON fallback turns")
    func liveAnthropicJSONFallback() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "json_search",
                    content: [
                        ["type": "text", "text": "JSON BEFORE"],
                        searchToolBlock(id: "json_private_search", query: "Swift JSON"),
                    ],
                    stopReason: "tool_use",
                    inputTokens: 2,
                    outputTokens: 3
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "json_final",
                    content: [["type": "text", "text": "JSON AFTER"]],
                    stopReason: "end_turn",
                    inputTokens: 4,
                    outputTokens: 5
                )
            ),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.webSearchResponse(
            context: gatewayLiveContext(fixture: fixture)
        )
        #expect(response.body.contentLength == nil)
        let body = try await responseBodyData(response.body)
        let stream = try #require(String(bytes: body, encoding: .utf8))

        #expect(stream.contains(#""text":"JSON BEFORE""#))
        #expect(stream.contains(#""text":"JSON AFTER""#))
        #expect(stream.contains(#""web_search_requests":1"#))
        #expect(!stream.contains("json_private_search"))
        #expect(stream.components(separatedBy: "event: message_stop\n").count - 1 == 1)

        let requests = await transport.requests
        try #require(requests.count == 3)
        #expect(try anthropicObject(requests[0].body)["stream"] as? Bool == true)
        #expect(try anthropicObject(requests[2].body)["stream"] as? Bool == true)
    }

    @Test("A post-commit provider failure emits one safe Anthropic error terminal")
    func liveAnthropicPostCommitFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let firstBody = GatewayGatedBody(
            chunks: [try gatewayProviderSSE(searchedProviderTurnFrames())]
        )
        let transport = RecordingGatewayTransport(responses: [
            gatewayStreamingResponse(firstBody),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .internalServerError, body: #"{"secret":"provider-body"}"#),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.webSearchResponse(
            context: gatewayLiveContext(fixture: fixture)
        )
        let recorder = StreamingStageRecorder()
        await #expect(throws: GatewayCommittedStreamFailure.self) {
            try await response.body.write(
                ObservingResponseBodyWriter(recorder: recorder)
            )
        }
        let body = await recorder.body
        let stream = try #require(String(bytes: body, encoding: .utf8))

        #expect(stream.components(separatedBy: "event: error\n").count - 1 == 1)
        #expect(!stream.contains("event: message_stop\n"))
        #expect(!stream.contains("provider-body"))
        #expect(!stream.contains("secret"))
    }

    @Test("The first live provider error remains transparent and lazy")
    func liveAnthropicFirstProviderFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let privateBody = #"{"error":{"message":"provider-limit"}}"#
        let transport = RecordingGatewayTransport(responses: [
            response(status: .tooManyRequests, body: privateBody)
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let response = try await responder.webSearchResponse(
            context: gatewayLiveContext(fixture: fixture)
        )

        #expect(response.status.code == 429)
        let body = try await responseBodyData(response.body)
        #expect(try #require(String(bytes: body, encoding: .utf8)) == privateBody)
        #expect(await transport.requests.count == 1)
    }

    func gatewayLiveContext(
        fixture: GatewayFixture
    ) throws -> GatewayWebSearchContext {
        let target = try #require(fixture.snapshot.resolve(model: "claude-opus-5"))
        let body = webSearchRequest(streaming: true, maximumUses: 2)
            .replacingOccurrences(
                of: #""max_uses":2"#,
                with:
                    #""max_uses":2,"allowed_domains":["swift.org"],"user_location":{"type":"approximate","city":"Paris","region":"Ile-de-France","country":"FR"}"#
            )
        let candidate = try AnthropicWebSearch.prepare(
            body: Data(body.utf8),
            targetModel: target.modelID,
            configuration: fixture.snapshot.webSearch
        )
        return GatewayWebSearchContext(
            prepared: try #require(candidate),
            configuration: fixture.snapshot.webSearch,
            target: target,
            providerCredential: "selected-secret",
            incomingHeaders: [:],
            eventID: UUID()
        )
    }
}
