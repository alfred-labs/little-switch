import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway Responses image policy")
struct GatewayResponsesImageInputTests {
    @Test(
        "A precise image rejection retries one text copy on the same wire",
        arguments: [ModelImageInputWire.responses, .chatCompletions])
    func rejection(wire: ModelImageInputWire) async throws {
        let fixture = try await GatewayImageFixture.make(wire: wire)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .ok, body: fixture.answer),
        ])
        try await fixture.application(transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: fixture.body))
            #expect(result.status == .ok)
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url == requests[1].url)
        #expect(
            try requests.allSatisfy { try ResponsesCompactionFixture.object($0.body)["model"] as? String == "model" })
        #expect(try GatewayImageFixture.containsImage(requests[0].body, wire: wire))
        #expect(try !GatewayImageFixture.containsImage(requests[1].body, wire: wire))
        let observations = await fixture.registry.observations()
        #expect(observations.count == 1)
        #expect(
            try observations[0].key
                == ModelImageInputPolicyResolver.key(provider: fixture.provider, modelID: "model", wire: wire))
        #expect(observations[0].verdict == .unsupported)
        #expect(observations[0].source == .providerRejection)
        #expect(await fixture.prober.calls == 0)
        await fixture.registry.shutdown()
    }

    @Test(
        "Auth, quota and unrelated validation errors never learn unsupported or retry",
        arguments: [400, 401, 403, 429, 500])
    func unrelatedErrors(status: Int) async throws {
        let fixture = try await GatewayImageFixture.make(wire: .chatCompletions)
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .init(statusCode: status),
                body: status == 400
                    ? #"{"error":{"code":"1210","message":"Invalid tools"}}"# : GatewayImageFixture.rejection)
        ])
        try await fixture.application(transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: fixture.body))
            #expect(result.status.code == status)
        }
        #expect(await transport.requests.count == 1)
        #expect(await fixture.registry.observations().isEmpty)
        await fixture.registry.shutdown()
    }

    @Test("An unknown image is probed before the only business permit; text input is never probed")
    func lazyProbe() async throws {
        let fixture = try await GatewayImageFixture.make(wire: .chatCompletions, advertised: nil)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: fixture.answer), response(status: .ok, body: fixture.answer),
        ])
        try await fixture.application(transport).test(.router) { client in
            let text = try ResponsesCompactionFixture.data(["model": fixture.slug, "input": "hello"])
            _ = try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: text))
            #expect(await fixture.prober.calls == 0)
            let result = try await withAsyncTestTimeout(description: "lazy probe before provider limit one") {
                try await client.execute(uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: fixture.body))
            }
            #expect(result.status == .ok)
        }
        #expect(await fixture.prober.calls == 1)
        #expect(await fixture.state.sessionRequestCount == 2)
        #expect(await fixture.state.requestPoolSnapshot().totalRunning == 0)
        #expect(
            try !GatewayImageFixture.containsImage(
                try #require(await transport.requests.last).body, wire: .chatCompletions))
        await fixture.registry.shutdown()
    }

    @Test("A repeated image error terminates the turn after exactly one text retry")
    func repeatedRejection() async throws {
        let fixture = try await GatewayImageFixture.make(wire: .chatCompletions)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .badRequest, body: GatewayImageFixture.rejection),
        ])
        try await fixture.application(transport).test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: fixture.body))
            #expect(result.status == .badRequest)
        }
        #expect(await transport.requests.count == 2)
        #expect(await fixture.registry.observations().count == 1)
        await fixture.registry.shutdown()
    }

    @Test("A stale client catalog cannot override an image rejection learned by the running gateway")
    func staleClientCatalog() async throws {
        let fixture = try await GatewayImageFixture.make(wire: .chatCompletions)
        let transport = RecordingGatewayTransport(responses: [
            response(status: .badRequest, body: GatewayImageFixture.rejection),
            response(status: .ok, body: fixture.answer),
            response(status: .ok, body: fixture.answer),
        ])
        let original = try fixture.body
        try await fixture.application(transport).test(.router) { client in
            for _ in 0..<2 {
                let result = try await client.execute(
                    uri: "/v1/responses", method: .post, body: ByteBuffer(bytes: original))
                #expect(result.status == .ok)
            }
        }
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(try !GatewayImageFixture.containsImage(requests[2].body, wire: .chatCompletions))
        #expect(try fixture.body == original)
        #expect(await fixture.prober.calls == 0)
        await fixture.registry.shutdown()
    }
}

struct GatewayImageFixture: Sendable {
    let provider: Provider
    let state: GatewayState
    let registry: ModelImageInputRegistry
    let prober: ImmediateImageTestProber
    let wire: ModelImageInputWire

    var slug: String { "example/model" }
    var body: Data {
        get throws { try ResponsesCompactionFixture.data(["model": slug, "input": [Self.imageMessage]]) }
    }
    var answer: String {
        wire == .responses
            ? #"{"id":"resp_done","status":"completed","output":[],"usage":{"input_tokens":1,"output_tokens":1}}"#
            : responsesModelResponse(id: "done", output: [])
    }

    static let rejection =
        #"{"error":{"code":"1210","message":"messages.content.type is invalid, allowed values: ['text']"}}"#
    static var imageMessage: [String: Any] {
        [
            "type": "message", "role": "user",
            "content": [["type": "input_image", "image_url": "data:image/png;base64,aGVsbG8="]],
        ]
    }

    static func make(wire: ModelImageInputWire, advertised: Bool? = true) async throws -> Self {
        let provider = Provider(
            name: "Example",
            baseURL: "https://provider.example",
            authMode: .none,
            models: [DiscoveredModel(id: "model", supportsImageInput: advertised)],
            status: .ready,
            maximumParallelRequests: 1,
            responsesWireOverride: wire == .chatCompletions ? .chatCompletions : nil)
        let admission = ModelImageProbeAdmission()
        let prober = ImmediateImageTestProber()
        let registry = ModelImageInputRegistry(prober: prober, admission: admission)
        try await registry.configure(provider: provider, generation: UUID())
        let state = GatewayState(
            snapshot: RoutingSnapshot(
                generation: 0,
                providers: [provider],
                mappings: [:],
                codex: CodexConfiguration(defaultModel: ModelMapping(providerID: provider.id, modelID: "model"))),
            routingMutationGuard: GatewayRoutingMutationGuard(),
            responsesCapabilities: ResponsesCapabilityLedger(),
            imageInputRegistry: registry)
        await admission.bind(state)
        return Self(provider: provider, state: state, registry: registry, prober: prober, wire: wire)
    }

    func application(_ transport: any UpstreamTransport) -> Application<GatewayResponder> {
        Application(
            responder: GatewayResponder(
                state: state, transport: transport, secretStore: MemorySecretStore(), requiredAuthorityPort: nil))
    }

    static func containsImage(_ body: Data, wire: ModelImageInputWire) throws -> Bool {
        if wire == .responses {
            return try !ResponsesImageInputProjection.project(body: body, acceptsImages: true).imageItemIndices.isEmpty
        }
        let root = try ResponsesCompactionFixture.object(body)
        let messages = root["messages"] as? [[String: Any]] ?? []
        return messages.contains { message in
            (message["content"] as? [[String: Any]] ?? []).contains { $0["type"] as? String == "image_url" }
        }
    }
}

actor ImmediateImageTestProber: ModelImageInputProbing {
    private(set) var calls = 0
    func probe(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?
    ) async throws -> ModelImageInputProbeResult {
        calls += 1
        return ModelImageInputProbeResult(outcome: .unsupported, usage: nil, startedAt: Date(), durationSeconds: 0)
    }
}
