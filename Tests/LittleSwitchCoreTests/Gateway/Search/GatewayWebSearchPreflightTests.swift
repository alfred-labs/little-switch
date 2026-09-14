import Foundation
import Hummingbird
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway web-search preflight")
struct GatewayWebSearchPreflightTests {
    @Test("Zero-budget Anthropic preflight ignores supplied and stored search credentials")
    func anthropicZeroBudgetNeedsNoCredential() throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let base = try GatewayTests().gatewayLiveContext(fixture: fixture)
        let candidate = try AnthropicWebSearch.prepare(
            body: Data(webSearchRequest(streaming: true, maximumUses: 2).utf8),
            targetModel: base.target.modelID,
            configuration: .disabled
        )
        let prepared = try #require(candidate)
        #expect(prepared.maximumUses == 0)
        #expect(prepared.privateToolName == nil)
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: ThrowingGatewaySecretStore(),
            requiredAuthorityPort: nil
        )
        for credential: String? in [nil, "preloaded-search-value"] {
            let context = GatewayWebSearchContext(
                prepared: prepared,
                configuration: base.configuration,
                target: base.target,
                providerCredential: base.providerCredential,
                incomingHeaders: base.incomingHeaders,
                eventID: UUID(),
                searchCredential: credential
            )
            switch responder.webSearchPreflight(context: context) {
            case .ready(let searchCredential):
                #expect(searchCredential == nil)
            case .rejected:
                Issue.record("Zero search budget must not require a search credential")
            }
        }
    }

    @Test("Anthropic preflight uses a supplied search credential and rejects oversized bodies")
    func anthropicCredentialAndBodyBound() async throws {
        let fixture = try GatewayTests().makeWebSearchFixture()
        let base = try GatewayTests().gatewayLiveContext(fixture: fixture)
        let direct = GatewayWebSearchContext(
            prepared: base.prepared,
            configuration: base.configuration,
            target: base.target,
            providerCredential: base.providerCredential,
            incomingHeaders: base.incomingHeaders,
            eventID: base.eventID,
            searchCredential: "direct-search-secret"
        )
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: ThrowingGatewaySecretStore(),
            requiredAuthorityPort: nil
        )

        switch responder.webSearchPreflight(context: direct) {
        case .ready(let credential):
            #expect(credential == "direct-search-secret")
        case .rejected:
            Issue.record("Expected the supplied search credential to pass preflight")
        }

        let oversizedPrepared = PreparedWebSearchRequest(
            upstreamBody: Data(repeating: 0x61, count: 4),
            originalModel: base.prepared.originalModel,
            streaming: base.prepared.streaming,
            maximumUses: base.prepared.maximumUses,
            searchOptions: base.prepared.searchOptions
        )
        let oversized = GatewayWebSearchContext(
            prepared: oversizedPrepared,
            configuration: base.configuration,
            target: base.target,
            providerCredential: base.providerCredential,
            incomingHeaders: base.incomingHeaders,
            eventID: UUID(),
            searchCredential: "direct-search-secret"
        )
        let boundedResponder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            maximumRequestBytes: 3,
            requiredAuthorityPort: nil
        )

        guard
            case .rejected(let response) = boundedResponder.webSearchPreflight(
                context: oversized
            )
        else {
            Issue.record("Expected oversized Anthropic preflight rejection")
            return
        }
        #expect(response.status == .contentTooLarge)
        #expect(
            String(data: try await responseBodyData(response.body), encoding: .utf8)?
                .contains("Request body is too large") == true
        )
    }

    @Test("Responses preflight rejects an oversized original upstream body")
    func responsesBodyBound() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let base = try liveResponsesSearchContext(fixture: fixture)
        let prepared = PreparedResponsesWebSearchRequest(
            upstreamBody: Data(repeating: 0x61, count: 4),
            originalBody: base.prepared.originalBody,
            originalModel: base.prepared.originalModel,
            originalToolsJSON: base.prepared.originalToolsJSON,
            originalInputJSON: base.prepared.originalInputJSON,
            streaming: base.prepared.streaming,
            maximumUses: base.prepared.maximumUses,
            searchOptions: base.prepared.searchOptions
        )
        let context = GatewayResponsesWebSearchContext(
            prepared: prepared,
            configuration: base.configuration,
            target: base.target,
            providerCredential: base.providerCredential,
            searchCredential: base.searchCredential,
            incomingHeaders: base.incomingHeaders,
            eventID: UUID(),
            needsChatCompletionsAdapter: true
        )
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            maximumRequestBytes: 3,
            requiredAuthorityPort: nil
        )

        guard
            case .rejected(let response) = responder.responsesWebSearchPreflight(
                context: context
            )
        else {
            Issue.record("Expected oversized Responses preflight rejection")
            return
        }
        #expect(response.status == .contentTooLarge)
    }

    @Test("Responses preflight bounds an expanded streaming provider request")
    func responsesGeneratedBodyBound() async throws {
        let fixture = try await GatewayTests().makeResponsesWebSearchFixture()
        let context = try liveResponsesSearchContext(fixture: fixture)
        let unbounded = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
        let generated = try unbounded.responsesLiveModelRequest(
            body: context.prepared.upstreamBody,
            context: context
        ).body
        #expect(generated.count > context.prepared.upstreamBody.count)
        let maximum = generated.count - 1
        #expect(context.prepared.upstreamBody.count <= maximum)
        let bounded = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            maximumRequestBytes: maximum,
            requiredAuthorityPort: nil
        )

        guard
            case .rejected(let response) = bounded.responsesWebSearchPreflight(
                context: context
            )
        else {
            Issue.record("Expected expanded Responses request rejection")
            return
        }
        #expect(response.status == .badGateway)
        #expect(
            String(data: try await responseBodyData(response.body), encoding: .utf8)?
                .contains("Provider request failed") == true
        )
    }

    @Test("Responses preflight error mapping is safe and exhaustive")
    func responsesFailureMapping() async throws {
        let scenarios = [
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.providerNotReady,
                status: 503,
                message: "Provider is not ready"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.requestTooLarge,
                status: 413,
                message: "Request body is too large"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.providerFailed,
                status: 502,
                message: "Provider request failed"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.generatedRequestTooLarge,
                status: 502,
                message: "Provider request failed"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.invalidProviderResponse,
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.invalidProviderRequest("invalidRequest"),
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesWebSearchError.responseTooLarge,
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.providerNotReady,
                status: 503,
                message: "Provider is not ready"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.requestTooLarge,
                status: 413,
                message: "Request body is too large"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.providerFailed,
                status: 502,
                message: "Provider request failed"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.invalidProviderResponse,
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.invalidProviderRequest("invalidRequest"),
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.clientWriteFailed,
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayResponsesLiveError.providerTerminalFailed,
                status: 502,
                message: "Invalid provider response"
            ),
            PreflightFailureScenario(
                error: GatewayTestError.failure,
                status: 502,
                message: "Invalid provider request"
            ),
        ]

        for scenario in scenarios {
            let response = responsesWebSearchPreflightFailureResponse(for: scenario.error)
            #expect(response.status.code == scenario.status)
            #expect(
                String(data: try await responseBodyData(response.body), encoding: .utf8)?
                    .contains(scenario.message) == true
            )
        }
    }

}

private struct PreflightFailureScenario {
    let error: any Error
    let status: Int
    let message: String
}
