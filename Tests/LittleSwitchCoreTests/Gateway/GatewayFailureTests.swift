import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import NIOEmbedded
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("A loopback authority with the wrong or missing port is rejected")
    func authorityPortRequired() async throws {
        let fixture = try makeFixture()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                requiredAuthorityPort: 11_436
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/models", method: .get)
            #expect(result.status == .forbidden)
            #expect(String(buffer: result.body).contains("Loopback Host is required"))
        }
    }

    @Test("Catalog encoding failures return a safe local error")
    func catalogEncodingFailure() async throws {
        let fixture = try makeFixture()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(
                    serializer: FailingGatewaySerializer()
                )
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(uri: "/v1/models", method: .get)
            #expect(result.status == .internalServerError)
            #expect(String(buffer: result.body).contains("Could not encode model catalog"))
        }
    }

    @Test("Safe gateway JSON serialization never exposes unsupported values")
    func safeGatewayJSONSerializationFailure() {
        let privateValue = Date(timeIntervalSince1970: 1)
        let result = safeGatewayJSONData(["private": privateValue])
        let serializationFailure = safeGatewayJSONData(
            ["private": "value"],
            serializer: FailingGatewaySerializer()
        )

        #expect(result.isEmpty)
        #expect(serializationFailure.isEmpty)
    }

    @Test("Malformed token-count JSON has a specific safe error")
    func malformedTokenCountJSON() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages/count_tokens",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5""#)
            )
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Invalid token count request"))
        }
    }

    @Test("Token estimator failures return a safe local error")
    func tokenEstimatorFailure() async throws {
        let fixture = try makeFixture()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(
                    tokenEstimator: FailingGatewayTokenEstimator()
                )
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages/count_tokens",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"claude-opus-5","messages":[{"role":"user","content":"hello"}]}"#
                )
            )
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Invalid token count request"))
        }
    }

    @Test("Token count covers non-object and oversized bodies")
    func tokenCountBodyFailures() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: []),
            maximumRequestBytes: 2
        )
        try await app.test(.router) { client in
            let oversized = try await client.execute(
                uri: "/v1/messages/count_tokens",
                method: .post,
                body: ByteBuffer(string: "123")
            )
            #expect(oversized.status == .contentTooLarge)
        }

        let objectApp = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )
        try await objectApp.test(.router) { client in
            let nonObject = try await client.execute(
                uri: "/v1/messages/count_tokens",
                method: .post,
                body: ByteBuffer(string: "[]")
            )
            #expect(nonObject.status == .badRequest)
            #expect(String(buffer: nonObject.body).contains("Invalid token count request"))
        }
    }

    @Test("Request body stream failures are safe for Messages and Responses")
    func requestBodyStreamFailure() async throws {
        let fixture = try makeFixture()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )

        for path in ["/v1/messages", "/v1/responses"] {
            let request = Request(
                head: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: path),
                body: RequestBody(asyncSequence: FailingGatewayBodySequence())
            )
            let result =
                path == "/v1/messages"
                ? try await responder.messagesResponse(request, eventID: UUID())
                : try await responder.responsesResponse(request, eventID: UUID())
            #expect(result.status == .badRequest)
        }
    }

    @Test("Request body cancellation propagates and records cancellation for every body route")
    func requestBodyCancellation() async throws {
        let fixture = try makeFixture()
        let recorder = TrafficTestRecorder()
        let responder = GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: []),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )

        for path in ["/v1/messages", "/v1/responses", "/v1/messages/count_tokens"] {
            let request = Request(
                head: HTTPRequest(
                    method: .post,
                    scheme: "http",
                    authority: "localhost",
                    path: path
                ),
                body: RequestBody(asyncSequence: CancellingGatewayBodySequence())
            )
            let channel = EmbeddedChannel()
            let context = BasicRequestContext(
                source: ApplicationRequestContextSource(
                    channel: channel,
                    logger: Logger(label: #function)
                )
            )

            await #expect(throws: CancellationError.self) {
                _ = try await responder.respond(to: request, context: context)
            }
            _ = try channel.finish()
        }

        #expect(recorder.events.count == 3)
        #expect(recorder.events.allSatisfy { $0.lifecycle == .cancelled })
        #expect(recorder.events.allSatisfy { $0.finalStatus == nil })
    }

    @Test("Provider credential read failures are safe for Messages and Responses")
    func providerCredentialReadFailure() async throws {
        let fixture = try makeFixture()
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: ThrowingGatewaySecretStore(),
                requiredAuthorityPort: nil
            )
        )
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let messages = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
            )
            #expect(messages.status == .internalServerError)
            #expect(String(buffer: messages.body).contains("Could not read provider credential"))

            let responses = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
            )
            #expect(responses.status == .internalServerError)
            #expect(String(buffer: responses.body).contains("Could not read provider credential"))
        }
    }

    @Test("Request rewriting failures return client-specific safe errors")
    func requestRewritingFailures() async throws {
        let fixture = try providerFailureFixture(
            baseURL: "https://example.com/api",
            includeSecret: true
        )
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                dependencies: GatewayResponderDependencies(
                    serializer: FailingGatewaySerializer()
                )
            )
        )
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let messages = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
            )
            #expect(messages.status == .badRequest)
            #expect(String(buffer: messages.body).contains("Invalid message request"))

            let responses = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
            )
            #expect(responses.status == .badRequest)
            #expect(String(buffer: responses.body).contains("Invalid Responses request"))
        }
    }

    @Test("Provider builder failures return safe unavailable errors")
    func providerBuilderFailures() async throws {
        let fixture = try providerFailureFixture(baseURL: "not-a-provider-url", includeSecret: true)
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let messages = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
            )
            #expect(messages.status == .serviceUnavailable)
            #expect(String(buffer: messages.body).contains("Provider is not ready"))

            let responses = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
            )
            #expect(responses.status == .serviceUnavailable)
            #expect(String(buffer: responses.body).contains("Provider is not ready"))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Direct transport failures are safe and Responses cancellation propagates")
    func directTransportFailures() async throws {
        let fixture = try makeFixture()
        let slug = try responsesSlug(fixture)
        let failingApp = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: FailingGatewayTransport(error: GatewayTestError.privateFailure),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil
            )
        )
        try await failingApp.test(.router) { client in
            for (path, body) in [
                ("/v1/messages", #"{"model":"claude-opus-5","messages":[]}"#),
                ("/v1/responses", #"{"model":"\#(slug)","input":"hello"}"#),
            ] {
                let result = try await client.execute(
                    uri: path,
                    method: .post,
                    body: ByteBuffer(string: body)
                )
                #expect(result.status == .badGateway)
                #expect(!String(buffer: result.body).contains("private"))
            }
        }

        // The save-time probe would have learned this chat-completions-only
        // preset has no native /v1/responses route; cancellation replays on
        // that learned adapter wire.
        for provider in fixture.snapshot.providers where provider.name == "z.ai" {
            await fixture.state.responsesCapabilities.record(
                providerID: provider.id,
                supportsNative: false
            )
        }
        let cancellingApp = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: CancellingGatewayTransport(),
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil
            )
        )
        try await cancellingApp.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
            )
            #expect(result.status == .internalServerError)
        }
    }

    @Test("Stopped admissions reject direct Messages and Responses before transport")
    func directStoppedAdmissions() async throws {
        let fixture = try makeFixture()
        await fixture.state.stopAdmissions()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)
        let slug = try responsesSlug(fixture)

        try await app.test(.router) { client in
            let messages = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: #"{"model":"claude-opus-5","messages":[]}"#)
            )
            #expect(messages.status == .serviceUnavailable)

            let responses = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                body: ByteBuffer(string: #"{"model":"\#(slug)","input":"hello"}"#)
            )
            #expect(responses.status == .serviceUnavailable)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Expanded zstd bodies enforce the request limit")
    func expandedResponsesBodyLimit() async throws {
        let fixture = try makeFixture()
        let slug = try responsesSlug(fixture)
        let body = Data(
            #"{"model":"\#(slug)","input":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#
                .utf8
        )
        let compressed = try zstdCompressed(body)
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: fixture.secrets,
                maximumRequestBytes: compressed.count + 1,
                requiredAuthorityPort: nil
            )
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentEncoding: "zstd"],
                body: ByteBuffer(bytes: compressed)
            )
            #expect(result.status == .contentTooLarge)
            #expect(String(buffer: result.body).contains("Expanded request body is too large"))
        }
    }

    @Test("Invalid eligible Anthropic search preparation fails safely")
    func invalidAnthropicSearchPreparation() async throws {
        let fixture = try await makeResponsesWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(
                    string: #"{"model":"claude-opus-5","messages":[],"tools":{}}"#
                )
            )
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Invalid web search request"))
        }
        #expect(await transport.requests.isEmpty)
    }

    private func providerFailureFixture(
        baseURL: String,
        includeSecret: Bool
    ) throws -> GatewayFixture {
        let base = try makeFixture()
        let original = try #require(base.snapshot.providers.first)
        let provider = Provider(
            id: original.id,
            name: original.name,
            baseURL: baseURL,
            authMode: original.authMode,
            models: original.models,
        )
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: [provider],
            mappings: base.snapshot.mappings,
            codex: base.snapshot.codex,
            webSearch: base.snapshot.webSearch
        )
        let secrets = MemorySecretStore()
        if includeSecret {
            try secrets.write("selected-secret", providerID: provider.id)
        }
        return GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: secrets
        )
    }
}
