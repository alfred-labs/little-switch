import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Loopback gateway")
struct GatewayTests {
    @Test("Hello answers the client preconnect probe in the upstream shape")
    func helloEndpoint() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/api/hello",
                method: .get,
                headers: HTTPFields()
            )
            // The upstream API answers 200 with {"message":"hello"}; the
            // client's probe reads any other status as a failure.
            #expect(response.status == .ok)
            let body = try #require(
                JSONSerialization.jsonObject(
                    with: Data(response.body.readableBytesView)
                ) as? [String: Any]
            )
            #expect(body["message"] as? String == "hello")

            // The preconnect itself fires HEAD — same answer, no body read.
            let head = try await client.execute(
                uri: "/api/hello",
                method: .head,
                headers: HTTPFields()
            )
            #expect(head.status == .ok)

            let wrongMethod = try await client.execute(
                uri: "/api/hello",
                method: .post,
                headers: HTTPFields()
            )
            #expect(wrongMethod.status == .methodNotAllowed)
            #expect(wrongMethod.headers[.allow] == "GET")
        }
    }

    @Test("About reports the running build tag without authentication")
    func aboutEndpoint() async throws {
        let fixture = try makeFixture()
        let app = makeApplication(
            fixture: fixture,
            transport: RecordingGatewayTransport(responses: [])
        )

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/api/about",
                method: .get,
                headers: HTTPFields()
            )
            #expect(response.status == .ok)
            let body = try #require(
                JSONSerialization.jsonObject(
                    with: Data(response.body.readableBytesView)
                ) as? [String: Any]
            )
            #expect(body["name"] as? String == "LittleSwitch")
            #expect(body["version"] as? String == ApplicationBuild.developmentTag)

            let wrongMethod = try await client.execute(
                uri: "/api/about",
                method: .post,
                headers: HTTPFields()
            )
            #expect(wrongMethod.status == .methodNotAllowed)
            #expect(wrongMethod.headers[.allow] == "GET")
        }
    }

    @Test("Only the fixed surface is exposed to loopback hosts without Origin")
    func surfaceSecurity() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let validHeaders = HTTPFields()

        #expect(GatewaySecurity.isAllowedAuthority("localhost:11436"))
        #expect(GatewaySecurity.isAllowedAuthority("127.42.0.1:11436"))
        #expect(GatewaySecurity.isAllowedAuthority("[::1]:11436"))
        #expect(!GatewaySecurity.isAllowedAuthority("localhost"))
        #expect(!GatewaySecurity.isAllowedAuthority("localhost:11435"))
        #expect(!GatewaySecurity.isAllowedAuthority("example.com:11436"))
        #expect(!GatewaySecurity.isAllowedAuthority("  "))
        #expect(!GatewaySecurity.isAllowedAuthority("user@localhost:11436"))
        #expect(!GatewaySecurity.isAllowedAuthority("localhost:11436?origin=x"))
        #expect(!GatewaySecurity.isAllowedAuthority("127.word.0.1:11436"))
        #expect(!GatewaySecurity.isAllowedAuthority("127.256.0.1:11436"))

        try await app.test(.router) { client in
            let marker = try #require(HTTPField.Name("X-LittleSwitch-Claude-Gateway"))
            let health = try await client.execute(
                uri: "/health",
                method: .get,
                headers: validHeaders
            )
            #expect(health.status == .noContent)
            #expect(health.headers[marker] == "1")

            let wrongMethod = try await client.execute(
                uri: "/v1/models",
                method: .post,
                headers: validHeaders
            )
            #expect(wrongMethod.status == .methodNotAllowed)
            #expect(wrongMethod.headers[.allow] == "GET")

            let unknown = try await client.execute(
                uri: "/unknown",
                method: .get,
                headers: validHeaders
            )
            #expect(unknown.status == .notFound)

            let origin = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: [.origin: "https://example.com"]
            )
            #expect(origin.status == .forbidden)
        }
        let events = recorder.events
        #expect(events.map(\.path) == ["/v1/models", "/unknown", "/v1/models"])
        #expect(events.allSatisfy { $0.lifecycle != .inProgress })
    }

    @Test("Catalog and token count are local and require a valid mapping")
    func localEndpoints() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder
        )
        let headers: HTTPFields = [.contentType: "application/json"]

        try await app.test(.router) { client in
            let models = try await client.execute(
                uri: "/v1/models",
                method: .get,
                headers: headers
            )
            #expect(models.status == .ok)
            let catalog = try JSONDecoder().decode(ClaudeCatalogResponse.self, from: data(models.body))
            #expect(catalog.data.map(\.id) == ["claude-opus-5"])
            #expect(catalog.data.map(\.displayName) == ["Opus ↦"])

            let count = try await client.execute(
                uri: "/v1/messages/count_tokens",
                method: .post,
                headers: headers,
                body: ByteBuffer(
                    string: #"{"model":"claude-opus-5","messages":[{"role":"user","content":"hello"}]}"#
                )
            )
            #expect(count.status == .ok)
            let countObject = try #require(
                JSONSerialization.jsonObject(with: data(count.body)) as? [String: Int]
            )
            #expect((countObject["input_tokens"] ?? 0) > 0)

            let unknown = try await client.execute(
                uri: "/v1/messages/count_tokens",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"model":"claude-sonnet-5","messages":[]}"#)
            )
            #expect(unknown.status == .badRequest)
            #expect(await transport.requests.isEmpty)
        }
        #expect(recorder.events.count == 3)
        #expect(recorder.events.first?.path == "/v1/models")
        #expect(recorder.events.last?.lifecycle == .failed)
    }

    @Test("Malformed requests and oversized bodies fail before upstream admission")
    func inputValidation() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let recorder = TrafficTestRecorder()
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            trafficRecorder: recorder,
            maximumRequestBytes: 8
        )

        try await app.test(.router) { client in
            let malformed = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [:],
                body: ByteBuffer(string: "{")
            )
            #expect(malformed.status == .badRequest)

            let oversized = try await client.execute(
                uri: "/v1/messages",
                method: .post,
                headers: [:],
                body: ByteBuffer(string: "123456789")
            )
            #expect(oversized.status == .contentTooLarge)
            #expect(await transport.requests.isEmpty)
            #expect(await fixture.state.sessionRequestCount == 0)
        }
        #expect(recorder.events.count == 2)
        #expect(recorder.events.allSatisfy { $0.lifecycle == .failed })
        #expect(Set(recorder.events.compactMap(\.finalStatus)) == [400, 413])
    }

    @Test("Responses accepts zstd and returns OpenAI errors before admission")
    func responsesInputValidation() async throws {
        let fixture = try makeFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body:
                    #"{"id":"chatcmpl_1","created":1,"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let slug = CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let compressed = try zstdCompressed(
            Data(#"{"model":"\#(slug)","input":"hello"}"#.utf8)
        )

        try await app.test(.router) { client in
            let accepted = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .contentEncoding: "zstd",
                ],
                body: ByteBuffer(bytes: compressed)
            )
            #expect(accepted.status == .ok)

            for (encoding, body) in [
                ("gzip", Data(#"{"model":"\#(slug)"}"#.utf8)),
                ("zstd", Data("not-zstd".utf8)),
                // Unresolvable slugs now pass through natively, so the
                // pre-admission rejection case drops the model slug entirely.
                ("identity", Data(#"{"input":"hello"}"#.utf8)),
            ] {
                let rejected = try await client.execute(
                    uri: "/v1/responses",
                    method: .post,
                    headers: [.contentEncoding: encoding],
                    body: ByteBuffer(bytes: body)
                )
                #expect(rejected.status == (encoding == "gzip" ? .unsupportedMediaType : .badRequest))
                let object = try #require(
                    JSONSerialization.jsonObject(with: data(rejected.body)) as? [String: Any]
                )
                #expect(object["type"] == nil)
                #expect((object["error"] as? [String: Any])?["type"] as? String == "invalid_request_error")
            }
        }

        #expect(await transport.requests.count == 1)
        #expect(await fixture.state.codexSessionRequestCount == 1)
    }

    func makeFixture() throws -> GatewayFixture {
        let providerID = try #require(
            UUID(uuidString: "057265e6-9c83-4f9d-92a4-93986f1e30e5")
        )
        let provider = Provider(
            id: providerID,
            name: "z.ai",
            baseURL: ProviderPreset.zai.baseURL,
            authMode: .bearer,
            models: [
                DiscoveredModel(
                    id: "glm-5.2",
                    maxTokens: 131_072,
                    detectedContextWindow: 1_000_000
                )
            ],
            anthropicBaseURL: ProviderPreset.zai.anthropicBaseURL
        )
        let snapshot = RoutingSnapshot(
            generation: 7,
            providers: [provider],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: providerID, modelID: "glm-5.2")
            ],
            codex: CodexConfiguration(
                defaultModel: ModelMapping(providerID: providerID, modelID: "glm-5.2")
            )
        )
        let state = GatewayState(snapshot: snapshot)
        let secrets = MemorySecretStore()
        try secrets.write("selected-secret", providerID: providerID)
        return GatewayFixture(snapshot: snapshot, state: state, secrets: secrets)
    }

    func makeApplication(
        fixture: GatewayFixture,
        transport: any UpstreamTransport,
        trafficRecorder: any TrafficRecording = NoopTrafficRecorder(),
        maximumRequestBytes: Int = 64 * 1_024 * 1_024
    ) -> Application<GatewayResponder> {
        Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                maximumRequestBytes: maximumRequestBytes,
                requiredAuthorityPort: nil,
                trafficRecorder: trafficRecorder
            )
        )
    }

}

func header(_ name: String, in headers: [TrafficHeader]) -> String? {
    headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
}

struct GatewayFixture: Sendable {
    let snapshot: RoutingSnapshot
    let state: GatewayState
    let secrets: MemorySecretStore
}

struct RecordedGatewayRequest: Sendable {
    let url: String
    let headers: HTTPHeaders
    let body: Data
}

func recordedBody(_ body: HTTPClientRequest.Body?) async throws -> Data {
    var data = Data()
    guard let body else {
        return data
    }
    for try await var buffer in body {
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            data.append(contentsOf: bytes)
        }
    }
    return data
}

actor RecordingGatewayTransport: UpstreamTransport {
    enum Error: Swift.Error {
        case missingResponse
    }

    private(set) var requests: [RecordedGatewayRequest] = []
    private var responses: [HTTPClientResponse]
    /// Answers POSTs by URL-path suffix (e.g. "/v1/responses": 404) instead
    /// of FIFO — for callers whose requests race, like the concurrent
    /// endpoint probe. GETs and unmatched paths fall back to the FIFO queue.
    private let routeStatuses: [String: UInt]

    init(
        responses: [HTTPClientResponse],
        routeStatuses: [String: UInt] = [:]
    ) {
        self.responses = responses
        self.routeStatuses = routeStatuses
    }

    private func matchingRouteStatus(for path: String) -> UInt? {
        routeStatuses.first { path.contains($0.key) }?.value
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        let body = try await recordedBody(request.body)
        requests.append(RecordedGatewayRequest(url: request.url, headers: request.headers, body: body))
        let probedPath = request.method == .POST ? URL(string: request.url)?.path : nil
        if let probedPath, let status = matchingRouteStatus(for: probedPath) {
            return HTTPClientResponse(
                status: HTTPResponseStatus(statusCode: Int(status)),
                headers: ["content-type": "application/json"],
                body: .bytes(ByteBuffer(string: #"{"detail":"Not Found"}"#))
            )
        }
        guard !responses.isEmpty else {
            throw Error.missingResponse
        }
        return responses.removeFirst()
    }
}

actor CancellingGatewayTransport: UpstreamTransport {
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw CancellationError()
    }
}

final class TrafficTestRecorder: TrafficRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [UUID: TrafficEvent] = [:]
    private var order: [UUID] = []
    private var sequences: [UUID: UInt64] = [:]

    var events: [TrafficEvent] {
        lock.withLock { order.compactMap { storedEvents[$0] } }
    }

    func record(eventID: UUID, action: TrafficAction) {
        lock.withLock {
            let sequence = sequences[eventID, default: 0]
            sequences[eventID] = sequence &+ 1
            let record = TrafficRecord(
                eventID: eventID,
                sequence: sequence,
                timestamp: Date(),
                action: action
            )
            if var event = storedEvents[eventID] {
                event.apply(record)
                storedEvents[eventID] = event
            } else {
                order.append(eventID)
                storedEvents[eventID] = TrafficEvent(firstRecord: record)
            }
        }
    }
}

func response(status: HTTPResponseStatus, body: String) -> HTTPClientResponse {
    HTTPClientResponse(
        status: status,
        headers: ["content-type": "application/json"],
        body: .bytes(ByteBuffer(string: body))
    )
}

func streamingResponse(
    status: HTTPResponseStatus,
    headers: HTTPHeaders,
    chunks: [String]
) -> HTTPClientResponse {
    let stream = AsyncStream<ByteBuffer> { continuation in
        for chunk in chunks {
            continuation.yield(ByteBuffer(string: chunk))
        }
        continuation.finish()
    }
    return HTTPClientResponse(status: status, headers: headers, body: .stream(stream))
}

func data(_ buffer: ByteBuffer) -> Data {
    Data(buffer.readableBytesView)
}
