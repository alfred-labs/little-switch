import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Provider networking")
struct ProviderNetworkingTests {

    @Test("Discovery joins the base path and injects only provider authentication")
    func authenticatedDiscovery() async throws {
        let transport = RecordingTransport(responses: [
            response(
                status: .ok,
                body: #"{"data":[{"id":"glm-5.2"}]}"#
            ),
            response(status: .notFound, body: #"{"error":"not ollama"}"#),
        ])
        let client = ProviderClient(transport: transport)
        let provider = Provider(
            name: "z.ai",
            baseURL: "https://api.z.ai/api/anthropic",
            authMode: .bearer
        )

        let models = try await client.discover(provider: provider, secret: "key")
        #expect(models == [DiscoveredModel(id: "glm-5.2")])
        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://api.z.ai/api/anthropic/v1/models")
        #expect(request.method == .GET)
        #expect(request.headers["authorization"] == ["Bearer key"])
        #expect(request.headers["x-api-key"].isEmpty)
    }

    @Test("vLLM context metadata is discovered without an Ollama probe")
    func vLLMContextDiscovery() async throws {
        let transport = RecordingTransport(responses: [
            response(
                status: .ok,
                body: #"{"data":[{"id":"large","max_model_len":400000,"context_length":400000}]}"#
            )
        ])
        let client = ProviderClient(transport: transport)
        let provider = Provider(
            name: "vLLM",
            baseURL: "https://inference.example.com",
            authMode: .bearer
        )

        let models = try await client.discover(provider: provider, secret: "key")

        #expect(models == [DiscoveredModel(id: "large", detectedContextWindow: 400_000)])
        #expect(await transport.requests.count == 1)
    }

    @Test("Known contexts skip every Ollama probe")
    func knownContextsSkipOllama() async throws {
        let transport = RecordingTransport(responses: [
            response(
                status: .ok,
                body: #"{"data":[{"id":"large","context_length":400000},{"id":"small","max_model_len":32000}]}"#
            )
        ])
        let client = ProviderClient(transport: transport)
        let provider = Provider(
            name: "vLLM",
            baseURL: "https://inference.example.com",
            authMode: .bearer
        )

        let models = try await client.discover(provider: provider, secret: "key")

        #expect(models.map(\.detectedContextWindow) == [400_000, 32_000])
        #expect(await transport.requests.count == 1)
    }

    @Test("Ollama discovery enriches missing contexts from architecture-agnostic model info")
    func ollamaContextDiscovery() async throws {
        let transport = RecordingTransport(responses: [
            response(
                status: .ok,
                body: #"{"data":[{"id":"dense"},{"id":"moe"}]}"#
            ),
            response(status: .ok, body: #"{"version":"0.33.0"}"#),
            response(
                status: .ok,
                body: #"{"model_info":{"general.architecture":"custom","custom.context_length":262144}}"#
            ),
            response(
                status: .ok,
                body: #"{"model_info":{"general.architecture":"other","other.context_length":1000000}}"#
            ),
        ])
        let client = ProviderClient(transport: transport)
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none
        )

        let models = try await client.discover(provider: provider, secret: nil)

        #expect(
            models == [
                DiscoveredModel(id: "dense", detectedContextWindow: 262_144),
                DiscoveredModel(id: "moe", detectedContextWindow: 1_000_000),
            ])
        let requests = await transport.requests
        #expect(
            requests.map(\.url) == [
                "http://127.0.0.1:11434/v1/models",
                "http://127.0.0.1:11434/api/version",
                "http://127.0.0.1:11434/api/show",
                "http://127.0.0.1:11434/api/show",
            ])
        #expect(requests.map(\.method) == [.GET, .GET, .POST, .POST])
    }

    @Test("A failed Ollama probe leaves generic discovery usable")
    func nonOllamaDiscovery() async throws {
        let transport = RecordingTransport(responses: [
            response(status: .ok, body: #"{"data":[{"id":"custom"}]}"#),
            response(status: .notFound, body: #"{"error":"missing"}"#),
        ])
        let client = ProviderClient(transport: transport)
        let provider = Provider(
            name: "Custom",
            baseURL: "https://example.com",
            authMode: .xAPIKey
        )

        let models = try await client.discover(provider: provider, secret: "key")

        #expect(models == [DiscoveredModel(id: "custom")])
        let requests = await transport.requests
        #expect(requests.count == 2)
        let probe = try #require(requests.last)
        #expect(probe.url == "https://example.com/api/version")
        #expect(probe.headers["x-api-key"] == ["key"])
    }

    @Test("Missing or failing Ollama version probes leave every model unchanged")
    func missingOllamaVersions() async throws {
        let provider = Provider(
            name: "Custom",
            baseURL: "https://example.com",
            authMode: .none
        )
        let missingVersion = RecordingTransport(responses: [
            response(status: .ok, body: #"{"data":[{"id":"one"},{"id":"two"}]}"#),
            response(status: .ok, body: "{}"),
        ])
        let models = try await ProviderClient(transport: missingVersion).discover(
            provider: provider,
            secret: nil
        )
        #expect(models == [DiscoveredModel(id: "one"), DiscoveredModel(id: "two")])

        let failingVersion = ProviderStepTransport(steps: [
            .response(response(status: .ok, body: #"{"data":[{"id":"one"}]}"#)),
            .failure,
        ])
        let fallback = try await ProviderClient(transport: failingVersion).discover(
            provider: provider,
            secret: nil
        )
        #expect(fallback == [DiscoveredModel(id: "one")])

        let failingVersionBody = RecordingTransport(responses: [
            response(status: .ok, body: #"{"data":[{"id":"one"}]}"#),
            providerFailingBodyResponse(),
        ])
        let bodyFallback = try await ProviderClient(transport: failingVersionBody).discover(
            provider: provider,
            secret: nil
        )
        #expect(bodyFallback == [DiscoveredModel(id: "one")])
    }

    @Test("Failed and invalid Ollama show responses leave multiple models unenriched")
    func failedOllamaShows() async throws {
        let transport = ProviderStepTransport(steps: [
            .response(
                response(
                    status: .ok,
                    body: #"{"data":[{"id":"known","context_length":64000},{"id":"failed"},{"id":"invalid"}]}"#
                )
            ),
            .response(response(status: .ok, body: #"{"version":"0.33.0"}"#)),
            .failure,
            .response(response(status: .ok, body: #"{"model_info":{"architecture":"unknown"}}"#)),
        ])
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none
        )

        let models = try await ProviderClient(transport: transport).discover(
            provider: provider,
            secret: nil
        )

        #expect(
            models == [
                DiscoveredModel(id: "failed"),
                DiscoveredModel(id: "invalid"),
                DiscoveredModel(id: "known", detectedContextWindow: 64_000),
            ]
        )
        #expect(await transport.requests.count == 4)
    }
}

extension ProviderNetworkingTests {

    @Test("Discovery rejects upstream errors without exposing their body")
    func discoveryErrors() async {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none
        )
        let transport = RecordingTransport(responses: [response(status: .unauthorized, body: "secret")])
        let client = ProviderClient(transport: transport)
        await #expect(throws: ProviderClient.Error.httpStatus(401)) {
            try await client.discover(provider: provider, secret: nil)
        }
    }

    @Test("Discovery bounds, preserves, and handles empty successful response bodies")
    func discoveryBodyBoundaries() async throws {
        let provider = Provider(
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none
        )
        let oversized = RecordingTransport(responses: [
            response(status: .ok, body: #"{"data":[{"id":"model"}]}"#)
        ])
        await #expect(throws: NIOTooManyBytesError.self) {
            try await ProviderClient(transport: oversized, maximumCatalogBytes: 4).discover(
                provider: provider,
                secret: nil
            )
        }

        let failing = RecordingTransport(responses: [providerFailingBodyResponse()])
        await #expect(throws: ProviderResponseStreamError.self) {
            try await ProviderClient(transport: failing).discover(
                provider: provider,
                secret: nil
            )
        }

        let empty = RecordingTransport(responses: [response(status: .ok, body: "")])
        await #expect(throws: DecodingError.self) {
            try await ProviderClient(transport: empty).discover(
                provider: provider,
                secret: nil
            )
        }

        let exactBody = #"{"data":[{"id":"model","context_length":1}]}"#
        let exact = RecordingTransport(responses: [response(status: .ok, body: exactBody)])
        let models = try await ProviderClient(
            transport: exact,
            maximumCatalogBytes: exactBody.utf8.count
        ).discover(provider: provider, secret: nil)
        #expect(models == [DiscoveredModel(id: "model", detectedContextWindow: 1)])
    }

    private func response(status: HTTPResponseStatus, body: String) -> HTTPClientResponse {
        HTTPClientResponse(
            status: status,
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: body))
        )
    }

}

private actor RecordingTransport: UpstreamTransport {
    private(set) var requests: [HTTPClientRequest] = []
    private var responses: [HTTPClientResponse]

    init(responses: [HTTPClientResponse]) {
        self.responses = responses
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}

private actor ProviderStepTransport: UpstreamTransport {
    enum Step: Sendable {
        case response(HTTPClientResponse)
        case failure
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
        case .failure:
            throw ProviderResponseStreamError()
        }
    }
}

private struct ProviderResponseStreamError: Swift.Error {}

private func providerFailingBodyResponse() -> HTTPClientResponse {
    let stream = AsyncThrowingStream<ByteBuffer, any Swift.Error> { continuation in
        continuation.finish(throwing: ProviderResponseStreamError())
    }
    return HTTPClientResponse(status: .ok, body: .stream(stream))
}
