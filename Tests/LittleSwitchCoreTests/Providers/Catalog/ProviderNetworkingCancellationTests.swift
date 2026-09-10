import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension ProviderNetworkingTests {
    @Test("Ollama version transport cancellation aborts discovery")
    func versionTransportCancellation() async {
        let transport = ProviderCancellationTransport(steps: [
            .response(providerCancellationResponse(body: #"{"data":[{"id":"one"}]}"#)),
            .cancelled,
        ])

        await #expect(throws: CancellationError.self) {
            try await ProviderClient(transport: transport).discover(
                provider: providerCancellationFixture,
                secret: nil
            )
        }
        #expect(await transport.requests.map(\.url) == catalogAndVersionURLs)
    }

    @Test("Ollama version body cancellation aborts discovery")
    func versionBodyCancellation() async {
        let transport = ProviderCancellationTransport(steps: [
            .response(providerCancellationResponse(body: #"{"data":[{"id":"one"}]}"#)),
            .response(providerCancellationBodyFailure()),
        ])

        await #expect(throws: CancellationError.self) {
            try await ProviderClient(transport: transport).discover(
                provider: providerCancellationFixture,
                secret: nil
            )
        }
        #expect(await transport.requests.map(\.url) == catalogAndVersionURLs)
    }

    @Test("Ollama show transport cancellation aborts before later model probes")
    func showTransportCancellation() async {
        let transport = ProviderCancellationTransport(steps: [
            .response(providerCancellationResponse(body: missingContextCatalog)),
            .response(providerCancellationResponse(body: #"{"version":"0.33.0"}"#)),
            .cancelled,
            .response(providerCancellationResponse(body: "{}")),
        ])

        await #expect(throws: CancellationError.self) {
            try await ProviderClient(transport: transport).discover(
                provider: providerCancellationFixture,
                secret: nil
            )
        }
        #expect(await transport.requests.map(\.url) == firstShowURLs)
    }

    @Test("Ollama show body cancellation aborts before later model probes")
    func showBodyCancellation() async {
        let transport = ProviderCancellationTransport(steps: [
            .response(providerCancellationResponse(body: missingContextCatalog)),
            .response(providerCancellationResponse(body: #"{"version":"0.33.0"}"#)),
            .response(providerCancellationBodyFailure()),
            .response(providerCancellationResponse(body: "{}")),
        ])

        await #expect(throws: CancellationError.self) {
            try await ProviderClient(transport: transport).discover(
                provider: providerCancellationFixture,
                secret: nil
            )
        }
        #expect(await transport.requests.map(\.url) == firstShowURLs)
    }
}

private let providerCancellationFixture = Provider(
    name: "Local",
    baseURL: "http://127.0.0.1:11434",
    authMode: .none
)

private let catalogAndVersionURLs = [
    "http://127.0.0.1:11434/v1/models",
    "http://127.0.0.1:11434/api/version",
]

private let firstShowURLs =
    catalogAndVersionURLs + [
        "http://127.0.0.1:11434/api/show"
    ]

private let missingContextCatalog = #"{"data":[{"id":"one"},{"id":"two"}]}"#

private actor ProviderCancellationTransport: UpstreamTransport {
    enum Step: Sendable {
        case response(HTTPClientResponse)
        case cancelled
    }

    private(set) var requests: [HTTPClientRequest] = []
    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        requests.append(request)
        switch steps.removeFirst() {
        case .response(let response):
            return response
        case .cancelled:
            throw CancellationError()
        }
    }
}

private func providerCancellationResponse(body: String) -> HTTPClientResponse {
    HTTPClientResponse(
        status: .ok,
        headers: ["content-type": "application/json"],
        body: .bytes(ByteBuffer(string: body))
    )
}

private func providerCancellationBodyFailure() -> HTTPClientResponse {
    let stream = AsyncThrowingStream<ByteBuffer, any Swift.Error> { continuation in
        continuation.finish(throwing: CancellationError())
    }
    return HTTPClientResponse(status: .ok, body: .stream(stream))
}
