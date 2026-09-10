import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

enum CoverageWriterFailure: Equatable, Sendable {
    case none
    case cancellation
    case error
}

struct CoverageThrowingWriter: ResponseBodyWriter {
    let failure: CoverageWriterFailure

    mutating func write(_ buffer: ByteBuffer) async throws {
        _ = buffer
        switch failure {
        case .none:
            return
        case .cancellation:
            throw CancellationError()
        case .error:
            throw GatewayTestError.privateFailure
        }
    }

    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
        _ = trailingHeaders
    }
}

func coverageResponder(
    fixture: GatewayFixture,
    transport: any UpstreamTransport,
    maximumRequestBytes: Int = 64 * 1_024 * 1_024,
    maximumErrorBytes: Int = 8 * 1_024 * 1_024
) -> GatewayResponder {
    GatewayResponder(
        state: fixture.state,
        transport: transport,
        secretStore: fixture.secrets,
        maximumRequestBytes: maximumRequestBytes,
        maximumErrorBytes: maximumErrorBytes,
        requiredAuthorityPort: nil
    )
}

func coverageResponse<S: AsyncSequence & Sendable>(
    _ sequence: S,
    contentType: String
) -> HTTPClientResponse where S.Element == ByteBuffer {
    HTTPClientResponse(
        status: .ok,
        headers: ["content-type": contentType],
        body: .stream(sequence)
    )
}

func coverageBytesResponse(
    _ data: Data,
    contentType: String
) -> HTTPClientResponse {
    HTTPClientResponse(
        status: .ok,
        headers: ["content-type": contentType],
        body: .bytes(ByteBuffer(bytes: data))
    )
}

func anthropicContext(
    _ context: GatewayWebSearchContext,
    providerBaseURL: String
) -> GatewayWebSearchContext {
    let provider = Provider(
        id: context.target.provider.id,
        name: context.target.provider.name,
        baseURL: providerBaseURL,
        authMode: context.target.provider.authMode,
        models: context.target.provider.models
    )
    return GatewayWebSearchContext(
        prepared: context.prepared,
        configuration: context.configuration,
        target: RoutedTarget(
            route: context.target.route,
            provider: provider,
            modelID: context.target.modelID
        ),
        providerCredential: context.providerCredential,
        incomingHeaders: context.incomingHeaders,
        eventID: context.eventID
    )
}

func responsesContext(
    _ context: GatewayResponsesWebSearchContext,
    providerBaseURL: String? = nil,
    providerCredential: String? = "selected-secret"
) -> GatewayResponsesWebSearchContext {
    let provider =
        providerBaseURL.map {
            Provider(
                id: context.target.provider.id,
                name: context.target.provider.name,
                baseURL: $0,
                authMode: context.target.provider.authMode,
                models: context.target.provider.models
            )
        } ?? context.target.provider
    return GatewayResponsesWebSearchContext(
        prepared: context.prepared,
        configuration: context.configuration,
        target: CodexModelTarget(provider: provider, model: context.target.model),
        providerCredential: providerCredential,
        searchCredential: context.searchCredential,
        incomingHeaders: context.incomingHeaders,
        eventID: context.eventID,
        needsChatCompletionsAdapter: true
    )
}
