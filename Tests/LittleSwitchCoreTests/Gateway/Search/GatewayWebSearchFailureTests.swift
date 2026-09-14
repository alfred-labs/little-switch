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
    @Test("Anthropic projection failures return a safe gateway error")
    func webSearchProjectionFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: [
                    response(
                        status: .ok,
                        body: anthropicModelResponse(
                            id: "msg_final",
                            content: [["type": "text", "text": "private-provider-output"]],
                            stopReason: "end_turn"
                        )
                    )
                ]),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(
                    projector: FailingGatewayWebSearchProjector()
                )
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 1))
            )
            #expect(result.status == .badGateway)
            let body = String(buffer: result.body)
            #expect(body.contains("Could not project provider response"))
            #expect(!body.contains("private-provider-output"))
        }
    }

    @Test("Missing and throwing Firecrawl secrets are handled safely")
    func webSearchSecretFailures() async throws {
        let missingFixture = try makeWebSearchFixture()
        try missingFixture.secrets.delete(account: .webSearch(.firecrawl))
        let missingTransport = SteppingGatewayTransport(steps: [
            .response(
                response(
                    status: .ok,
                    body: anthropicModelResponse(
                        id: "msg_search",
                        content: [searchToolBlock(id: "search", query: "Swift")],
                        stopReason: "tool_use"
                    )
                )
            ),
            .response(
                response(
                    status: .ok,
                    body: anthropicModelResponse(
                        id: "msg_final",
                        content: [["type": "text", "text": "Unavailable"]],
                        stopReason: "end_turn"
                    )
                )
            ),
        ])
        let missingApp = makeApplication(fixture: missingFixture, transport: missingTransport)
        try await missingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 1))
            )
            #expect(result.status == .ok)
        }
        #expect(await missingTransport.requests.count == 2)

        let throwingFixture = try makeWebSearchFixture()
        let throwingTransport = RecordingGatewayTransport(responses: [])
        let throwingApp = Application(
            responder: GatewayResponder(
                state: throwingFixture.state,
                transport: throwingTransport,
                secretStore: SearchThrowingGatewaySecretStore(
                    providerID: throwingFixture.snapshot.providers[0].id,
                    providerSecret: "selected-secret"
                ),
                requiredAuthorityPort: nil
            )
        )
        try await throwingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 1))
            )
            #expect(result.status == .internalServerError)
            let body = String(buffer: result.body)
            #expect(body.contains("Could not read web search credential"))
            #expect(!body.contains("private"))
        }
        #expect(await throwingTransport.requests.isEmpty)
    }

    @Test("Stopped admission and an unready provider prevent Anthropic search transport")
    func webSearchAdmissionAndProviderReadiness() async throws {
        let stoppedFixture = try makeWebSearchFixture()
        await stoppedFixture.state.stopAdmissions()
        let stoppedTransport = RecordingGatewayTransport(responses: [])
        let stoppedApp = makeApplication(fixture: stoppedFixture, transport: stoppedTransport)
        try await stoppedApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 1))
            )
            #expect(result.status == .serviceUnavailable)
        }
        #expect(await stoppedTransport.requests.isEmpty)

        let fixture = try makeWebSearchFixture()
        let context = try makeWebSearchContext(
            fixture: fixture,
            providerBaseURL: "not-a-provider-url"
        )
        let transport = RecordingGatewayTransport(responses: [])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let result = try await responder.webSearchResponse(context: context)
        #expect(result.status == .serviceUnavailable)
        let body = String(data: try await responseBodyData(result.body), encoding: .utf8) ?? ""
        #expect(!body.contains("not-a-provider-url"))
        #expect(await transport.requests.isEmpty)
    }

    @Test("Anthropic model transport and body failures are safe while cancellation propagates")
    func webSearchModelFailures() async throws {
        let fixture = try makeWebSearchFixture()
        let context = try makeWebSearchContext(fixture: fixture)

        for step in [
            GatewayTransportStep.failure(.privateFailure),
            GatewayTransportStep.response(response(status: .ok, body: "private-oversized")),
            GatewayTransportStep.response(failingResponse(error: GatewayTestError.privateFailure)),
            GatewayTransportStep.response(response(status: .badGateway, body: "private-oversized")),
            GatewayTransportStep.response(failingResponse(status: .badGateway, error: GatewayTestError.privateFailure)),
        ] {
            let responder = GatewayResponder(
                state: GatewayState(snapshot: fixture.snapshot),
                transport: SteppingGatewayTransport(steps: [step]),
                secretStore: fixture.secrets,
                maximumErrorBytes: 4,
                requiredAuthorityPort: nil
            )
            let result = try await responder.webSearchResponse(context: context)
            #expect(result.status == .badGateway)
            let body = String(data: try await responseBodyData(result.body), encoding: .utf8) ?? ""
            #expect(body.contains("Provider request failed"))
            #expect(!body.contains("private"))
        }

        for step in [
            GatewayTransportStep.cancellation,
            GatewayTransportStep.response(failingResponse(error: CancellationError())),
            GatewayTransportStep.response(failingResponse(status: .badGateway, error: CancellationError())),
        ] {
            let responder = GatewayResponder(
                state: GatewayState(snapshot: fixture.snapshot),
                transport: SteppingGatewayTransport(steps: [step]),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil
            )
            await #expect(throws: CancellationError.self) {
                _ = try await responder.webSearchResponse(context: context)
            }
        }
    }

    @Test("A malformed Anthropic follow-up returns a safe provider error")
    func malformedWebSearchFollowUp() async throws {
        let fixture = try makeWebSearchFixture()
        var context = try makeWebSearchContext(fixture: fixture)
        context = GatewayWebSearchContext(
            prepared: PreparedWebSearchRequest(
                upstreamBody: Data(#"{"tools":[{"name":"web_search"}]}"#.utf8),
                originalModel: context.prepared.originalModel,
                streaming: false,
                maximumUses: 1
            ),
            configuration: context.configuration,
            target: context.target,
            providerCredential: context.providerCredential,
            incomingHeaders: context.incomingHeaders,
            eventID: context.eventID
        )
        let transport = SteppingGatewayTransport(steps: [
            .response(
                response(
                    status: .ok,
                    body: anthropicModelResponse(
                        id: "msg_search",
                        content: [searchToolBlock(id: "search", query: "Swift")],
                        stopReason: "tool_use"
                    )
                )
            ),
            .response(response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#)),
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.webSearchResponse(context: context)
        #expect(result.status == .badGateway)
        #expect(
            String(data: try await responseBodyData(result.body), encoding: .utf8)?.contains(
                "Invalid provider response") == true)
    }

    @Test(
        "Malformed Anthropic model output is rejected before search",
        arguments: [
            "private malformed provider output", #"{"content":[]}"#,
        ])
    func malformedAnthropicModelOutput(providerBody: String) async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: providerBody)
        ])
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let result = try await responder.webSearchResponse(
            context: makeWebSearchContext(fixture: fixture)
        )

        #expect(result.status == .badGateway)
        let body = String(data: try await responseBodyData(result.body), encoding: .utf8) ?? ""
        #expect(body.contains("Invalid provider response"))
        #expect(!body.contains("private malformed provider output"))
        #expect(await transport.requests.count == 1)
    }

    @Test("Cancellation between Firecrawl and the Anthropic follow-up propagates")
    func cancellationBetweenAnthropicSearchTurns() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = CancellingAnthropicSearchTransport(
            firstResponse: response(
                status: .ok,
                body: anthropicModelResponse(
                    id: "msg_search",
                    content: [searchToolBlock(id: "search", query: "Swift")],
                    stopReason: "tool_use"
                )
            )
        )
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let task = Task {
            try await responder.webSearchResponse(
                context: makeWebSearchContext(fixture: fixture)
            )
        }
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transport.requestCount == 2)
    }

    @Test("Admitted Anthropic search keeps its original provider and Firecrawl snapshot")
    func anthropicSearchImmutableAdmission() async throws {
        let fixture = try makeWebSearchFixture(maximumUses: 2)
        let replacement = try replacementAnthropicProvider()
        let transport = ReplacingAnthropicSearchTransport(
            state: fixture.state,
            replacement: replacement,
            responses: [
                response(
                    status: .ok,
                    body: anthropicModelResponse(
                        id: "msg_search",
                        content: [searchToolBlock(id: "search", query: "Swift")],
                        stopReason: "tool_use"
                    )
                ),
                response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
                response(
                    status: .ok,
                    body: anthropicModelResponse(
                        id: "msg_final",
                        content: [["type": "text", "text": "Done"]],
                        stopReason: "end_turn"
                    )
                ),
            ]
        )
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: webSearchRequest(streaming: false, maximumUses: 2))
            )
            #expect(result.status == .ok)
        }

        let requests = await transport.requests
        #expect(
            requests.map(\.url) == [
                "https://api.z.ai/api/anthropic/v1/messages",
                "https://api.firecrawl.dev/v2/search",
                "https://api.z.ai/api/anthropic/v1/messages",
            ]
        )
        try #require(requests.count == 3)
        let firecrawl = try anthropicObject(requests[1].body)
        #expect(firecrawl["limit"] as? Int == 10)
        let followUp = try anthropicObject(requests[2].body)
        #expect(followUp["model"] as? String == "glm-5.2")
        let current = await fixture.state.capture()
        #expect(current.providers == [replacement])
        #expect(current.webSearch.resultsLimit == 99)
    }

    private func makeWebSearchContext(
        fixture: GatewayFixture,
        providerBaseURL: String? = nil
    ) throws -> GatewayWebSearchContext {
        let target = try #require(fixture.snapshot.resolve(model: "claude-opus-5"))
        let provider =
            providerBaseURL.map {
                Provider(
                    id: target.provider.id,
                    name: target.provider.name,
                    baseURL: $0,
                    authMode: target.provider.authMode,
                    models: target.provider.models
                )
            } ?? target.provider
        let effectiveTarget = RoutedTarget(
            route: target.route,
            provider: provider,
            modelID: target.modelID
        )
        let candidate = try AnthropicWebSearch.prepare(
            body: Data(webSearchRequest(streaming: false, maximumUses: 1).utf8),
            targetModel: target.modelID,
            configuration: fixture.snapshot.webSearch
        )
        let prepared = try #require(candidate)
        return GatewayWebSearchContext(
            prepared: prepared,
            configuration: fixture.snapshot.webSearch,
            target: effectiveTarget,
            providerCredential: "selected-secret",
            incomingHeaders: [:],
            eventID: UUID()
        )
    }
}

private actor CancellingAnthropicSearchTransport: UpstreamTransport {
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
        if requestCount == 2 {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#)
        }
        throw GatewayTestError.privateFailure
    }
}

private actor ReplacingAnthropicSearchTransport: UpstreamTransport {
    private let state: GatewayState
    private let replacement: Provider
    private var responses: [HTTPClientResponse]
    private(set) var requests: [RecordedGatewayRequest] = []

    init(state: GatewayState, replacement: Provider, responses: [HTTPClientResponse]) {
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
        requests.append(RecordedGatewayRequest(url: request.url, headers: request.headers, body: data))
        if requests.count == 1 {
            _ = await state.replace(
                providers: [replacement],
                mappings: [
                    "claude-opus-5": ModelMapping(
                        providerID: replacement.id,
                        modelID: replacement.models[0].id
                    )
                ],
                webSearch: WebSearchConfiguration(
                    provider: .firecrawl,
                    resultsLimit: 99,
                    maximumUses: 10
                )
            )
        }
        return responses.removeFirst()
    }
}

private func replacementAnthropicProvider() throws -> Provider {
    let id = try #require(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"))
    return Provider(
        id: id,
        name: "replacement",
        baseURL: "https://replacement.example/v1",
        authMode: .none,
        models: [DiscoveredModel(id: "replacement-model")]
    )
}
