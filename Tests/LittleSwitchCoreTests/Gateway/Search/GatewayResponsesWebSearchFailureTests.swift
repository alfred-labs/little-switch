import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Responses projection failures return a safe gateway error")
    func responsesProjectionFailure() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let slug = try responsesSlug(fixture)
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: [
                    response(status: .ok, body: responsesFinalResponse("private-provider-output"))
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
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .badGateway)
            let body = String(buffer: result.body)
            #expect(body.contains("Could not project provider response"))
            #expect(!body.contains("private-provider-output"))
        }
    }

    @Test("Responses handles missing and throwing Firecrawl secrets safely")
    func responsesSearchSecretFailures() async throws {
        let missingFixture = try await makeResponsesWebSearchFixture()
        try missingFixture.secrets.delete(account: .webSearch(.firecrawl))
        let missingTransport = SteppingGatewayTransport(steps: [
            .response(
                response(
                    status: .ok,
                    body: responsesSearchResponse(
                        id: "resp_search",
                        callID: "call_search",
                        query: "Swift"
                    )
                )
            ),
            .response(response(status: .ok, body: responsesFinalResponse("Unavailable"))),
        ])
        let missingApp = makeApplication(fixture: missingFixture, transport: missingTransport)
        let missingSlug = try responsesSlug(missingFixture)
        try await missingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: responsesWebSearchRequest(slug: missingSlug))
            )
            #expect(result.status == .ok)
        }
        #expect(await missingTransport.requests.count == 2)

        let throwingFixture = try await makeResponsesWebSearchFixture()
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
        let throwingSlug = try responsesSlug(throwingFixture)
        try await throwingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: responsesWebSearchRequest(slug: throwingSlug))
            )
            #expect(result.status == .internalServerError)
            let body = String(buffer: result.body)
            #expect(body.contains("Could not read web search credential"))
            #expect(!body.contains("private"))
        }
        #expect(await throwingTransport.requests.isEmpty)
    }

    @Test("Responses model failures are safe while cancellation propagates")
    func responsesSearchModelFailures() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let context = try makeResponsesSearchContext(fixture: fixture)

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
            let result = try await responder.responsesWebSearchResponse(context: context)
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
                _ = try await responder.responsesWebSearchResponse(context: context)
            }
        }
    }

    @Test("An unready Responses provider and malformed follow-up return safe errors")
    func responsesProviderReadinessAndMalformedFollowUp() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let invalidContext = try makeResponsesSearchContext(
            fixture: fixture,
            providerBaseURL: "not-a-provider-url"
        )
        let noTransport = RecordingGatewayTransport(responses: [])
        let invalidResponder = GatewayResponder(
            state: fixture.state,
            transport: noTransport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let invalidResult = try await invalidResponder.responsesWebSearchResponse(
            context: invalidContext
        )
        #expect(invalidResult.status == .serviceUnavailable)
        #expect(await noTransport.requests.isEmpty)

        var malformedContext = try makeResponsesSearchContext(fixture: fixture)
        malformedContext = GatewayResponsesWebSearchContext(
            prepared: PreparedResponsesWebSearchRequest(
                upstreamBody: Data("{}".utf8),
                originalBody: malformedContext.prepared.originalBody,
                originalModel: malformedContext.prepared.originalModel,
                originalToolsJSON: malformedContext.prepared.originalToolsJSON,
                originalInputJSON: malformedContext.prepared.originalInputJSON,
                streaming: false,
                maximumUses: 1
            ),
            configuration: malformedContext.configuration,
            target: malformedContext.target,
            providerCredential: malformedContext.providerCredential,
            searchCredential: malformedContext.searchCredential,
            incomingHeaders: malformedContext.incomingHeaders,
            eventID: malformedContext.eventID,
            needsChatCompletionsAdapter: true
        )
        let transport = SteppingGatewayTransport(steps: [
            .response(
                response(
                    status: .ok,
                    body: responsesSearchResponse(
                        id: "resp_search",
                        callID: "call_search",
                        query: "Swift"
                    )
                )
            ),
            .response(response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#)),
        ])
        let malformedResponder = GatewayResponder(
            state: GatewayState(snapshot: fixture.snapshot),
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let malformedResult = try await malformedResponder.responsesWebSearchResponse(
            context: malformedContext
        )
        #expect(malformedResult.status == .badGateway)
        #expect(
            String(data: try await responseBodyData(malformedResult.body), encoding: .utf8)?.contains(
                "Invalid provider response") == true)
    }

    @Test("Native Responses web search stays transparent and covers safe adapter failures")
    func nativeResponsesSearchTurns() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let nativeContext = try makeResponsesSearchContext(
            fixture: fixture,
            providerBaseURL: "https://example.com/api"
        )
        let searchTurn = nativeResponsesSearchResponse()
        let finalTurn = nativeResponsesFinalResponse()
        let successTransport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: searchTurn),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .ok, body: finalTurn),
        ])
        let successResponder = GatewayResponder(
            state: fixture.state,
            transport: successTransport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        #expect(
            try await successResponder.responsesWebSearchResponse(context: nativeContext).status
                == .ok
        )
        #expect(
            await successTransport.requests.filter { $0.url.contains("example.com") }.map(\.url)
                == [
                    "https://example.com/api/v1/responses",
                    "https://example.com/api/v1/responses",
                ]
        )

        let noCredentialContext = GatewayResponsesWebSearchContext(
            prepared: nativeContext.prepared,
            configuration: nativeContext.configuration,
            target: nativeContext.target,
            providerCredential: nil,
            searchCredential: nativeContext.searchCredential,
            incomingHeaders: nativeContext.incomingHeaders,
            eventID: UUID(),
            needsChatCompletionsAdapter: false
        )
        let noTransport = RecordingGatewayTransport(responses: [])
        let noCredentialResponder = GatewayResponder(
            state: fixture.state,
            transport: noTransport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        // Without a saved credential the turn still runs: the anonymous
        // request reaches the provider wire with no authorization header.
        #expect(
            try await noCredentialResponder.responsesWebSearchResponse(context: noCredentialContext)
                .status == .badGateway
        )
        let anonymousRequest = await noTransport.requests.first
        #expect(anonymousRequest?.headers["authorization"].isEmpty == true)

        let invalidResponder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [response(status: .ok, body: "{}")]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        #expect(
            try await invalidResponder.responsesWebSearchResponse(context: nativeContext).status
                == .badGateway
        )

        let malformedPrepared = PreparedResponsesWebSearchRequest(
            upstreamBody: Data(#"{"tools":[{"type":"function","name":"web_search"}]}"#.utf8),
            originalBody: nativeContext.prepared.originalBody,
            originalModel: nativeContext.prepared.originalModel,
            originalToolsJSON: nativeContext.prepared.originalToolsJSON,
            originalInputJSON: nativeContext.prepared.originalInputJSON,
            streaming: false,
            maximumUses: 1
        )
        let malformedContext = GatewayResponsesWebSearchContext(
            prepared: malformedPrepared,
            configuration: nativeContext.configuration,
            target: nativeContext.target,
            providerCredential: nativeContext.providerCredential,
            searchCredential: nativeContext.searchCredential,
            incomingHeaders: nativeContext.incomingHeaders,
            eventID: UUID(),
            needsChatCompletionsAdapter: false
        )
        let malformedResponder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [
                response(status: .ok, body: searchTurn),
                response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            ]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        #expect(
            try await malformedResponder.responsesWebSearchResponse(context: malformedContext).status
                == .badGateway
        )
    }

    @Test("Responses search IDs preserve non-response provider IDs")
    func responsesNonResponseSearchID() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "turn_one",
                    callID: "call_search",
                    query: "Swift"
                )
            ),
            response(status: .ok, body: #"{"success":true,"data":{"web":[]}}"#),
            response(status: .ok, body: responsesFinalResponse("Done")),
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: responsesWebSearchRequest(slug: slug))
            )
            #expect(result.status == .ok)
            let object = try responsesGatewayObject(data(result.body))
            let output = try #require(object["output"] as? [[String: Any]])
            #expect(output.first { $0["type"] as? String == "web_search_call" }?["id"] as? String == "ws_turn_one_1")
        }
    }

    @Test("Cancellation between Firecrawl and the Responses follow-up propagates")
    func cancellationBetweenResponsesSearchTurns() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = CancellingResponsesTurnTransport(
            firstResponse: response(
                status: .ok,
                body: responsesSearchResponse(
                    id: "resp_search",
                    callID: "call_search",
                    query: "Swift"
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
            try await responder.responsesWebSearchResponse(
                context: makeResponsesSearchContext(fixture: fixture)
            )
        }
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transport.requestCount == 2)
    }

    @Test("Cancellation returned with a valid Responses final turn still propagates")
    func cancellationWithResponsesFinalTurn() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = CancellingResponsesFinalTurnTransport()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        let task = Task {
            try await responder.responsesWebSearchResponse(
                context: makeResponsesSearchContext(fixture: fixture)
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transport.requestCount == 1)
    }

    private func makeResponsesSearchContext(
        fixture: GatewayFixture,
        providerBaseURL: String? = nil
    ) throws -> GatewayResponsesWebSearchContext {
        let mapping = try #require(
            fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers)
        )
        let originalTarget = try #require(
            fixture.snapshot.resolveCodex(model: CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers))
        )
        let provider =
            providerBaseURL.map {
                Provider(
                    id: originalTarget.provider.id,
                    name: originalTarget.provider.name,
                    baseURL: $0,
                    authMode: originalTarget.provider.authMode,
                    models: originalTarget.provider.models
                )
            } ?? originalTarget.provider
        let target = CodexModelTarget(provider: provider, model: originalTarget.model)
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let candidate = try OpenAIResponsesWebSearch.prepare(
            body: Data(responsesWebSearchRequest(slug: slug).utf8),
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
            needsChatCompletionsAdapter: providerBaseURL == nil
        )
    }
}

private actor CancellingResponsesTurnTransport: UpstreamTransport {
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

private actor CancellingResponsesFinalTurnTransport: UpstreamTransport {
    private(set) var requestCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        if let body = request.body {
            for try await _ in body {}
        }
        requestCount += 1
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        return response(status: .ok, body: responsesFinalResponse("Done"))
    }
}
