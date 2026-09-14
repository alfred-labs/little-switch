import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Stopped admissions prevent every Codex search upstream request")
    func responsesSearchStoppedAdmission() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        await fixture.state.stopAdmissions()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .serviceUnavailable)
        }
        #expect(await transport.requests.isEmpty)
        #expect(await fixture.state.codexSessionRequestCount == 0)
    }

    @Test("Malformed eligible search fails before admission")
    func responsesMalformedSearchBeforeAdmission() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)
        let request = #"{"model":"\#(slug)","tools":[{"type":"web_search"}]}"#

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: request)
            )
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Invalid Responses request"))
        }
        #expect(await transport.requests.isEmpty)
        #expect(await fixture.state.codexSessionRequestCount == 0)
    }

    @Test("Cancellation during Firecrawl propagates through the gateway lifecycle")
    func responsesSearchCancellation() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = CancellingResponsesSearchTransport(
            firstResponse: response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search",
                    callID: "call_search",
                    query: "Swift"
                )
            )
        )
        let recorder = TrafficTestRecorder()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                trafficRecorder: recorder
            )
        )
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .internalServerError)
        }
        #expect(await transport.requestCount == 2)
        #expect(await fixture.state.codexSessionRequestCount == 1)
        #expect(recorder.events.first?.lifecycle == .cancelled)
    }

    @Test("Admitted Codex search keeps its original provider and Firecrawl snapshot")
    func responsesSearchImmutableAdmission() async throws {
        let fixture = try await makeResponsesWebSearchFixture(maximumUses: 2, resultsLimit: 7)
        let replacement = try replacementResponsesProvider()
        let transport = ReplacingResponsesSearchTransport(
            state: fixture.state,
            replacement: replacement,
            responses: [
                response(
                    status: .ok,
                    body: responsesSearchResponse(
                        id: "resp_search",
                        callID: "call_search",
                        query: "Swift"
                    )
                ),
                response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
                response(status: .ok, body: responsesFinalResponse("Done")),
            ]
        )
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil
            )
        )
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .ok)
        }

        let requests = await transport.requests
        #expect(
            requests.map(\.url) == [
                "https://api.z.ai/api/coding/paas/v4/chat/completions",
                "https://api.firecrawl.dev/v2/search",
                "https://api.z.ai/api/coding/paas/v4/chat/completions",
            ]
        )
        try #require(requests.count == 3)
        let firecrawl = try responsesGatewayObject(requests[1].body)
        #expect(firecrawl["limit"] as? Int == 7)
        let followUp = try responsesGatewayObject(requests[2].body)
        #expect(followUp["model"] as? String == "glm-5.2")
        let current = await fixture.state.capture()
        #expect(current.providers == [replacement])
        #expect(current.webSearch.resultsLimit == 99)
    }
}

private actor CancellingResponsesSearchTransport: UpstreamTransport {
    private let firstResponse: HTTPClientResponse
    private(set) var requestCount = 0

    init(firstResponse: HTTPClientResponse) {
        self.firstResponse = firstResponse
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        if let body = request.body {
            for try await _ in body {}
        }
        requestCount += 1
        if requestCount == 1 {
            return firstResponse
        }
        throw CancellationError()
    }
}

private actor ReplacingResponsesSearchTransport: UpstreamTransport {
    private let state: GatewayState
    private let replacement: Provider
    private var responses: [HTTPClientResponse]
    private(set) var requests: [RecordedGatewayRequest] = []

    init(
        state: GatewayState,
        replacement: Provider,
        responses: [HTTPClientResponse]
    ) {
        self.state = state
        self.replacement = replacement
        self.responses = responses
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        var data = Data()
        if let body = request.body {
            for try await buffer in body {
                data.append(contentsOf: buffer.readableBytesView)
            }
        }
        requests.append(
            RecordedGatewayRequest(url: request.url, headers: request.headers, body: data)
        )
        if requests.count == 1 {
            _ = await state.replace(
                providers: [replacement],
                mappings: [:],
                codex: CodexConfiguration(defaultModel: replacementMapping),
                webSearch: WebSearchConfiguration(
                    provider: .firecrawl,
                    resultsLimit: 99,
                    maximumUses: 10
                )
            )
        }
        return responses.removeFirst()
    }

    private var replacementMapping: ModelMapping {
        ModelMapping(providerID: replacement.id, modelID: replacement.models[0].id)
    }
}

private func replacementResponsesProvider() throws -> Provider {
    let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
    return Provider(
        id: id,
        name: "replacement",
        baseURL: "https://replacement.example/v1",
        authMode: .none,
        models: [DiscoveredModel(id: "replacement-model")]
    )
}
