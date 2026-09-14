import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("Queued gateway requests keep one canonical body until admission")
    func transformationsRunAfterAdmission() async throws {
        let fixture = try makeFixture()
        var provider = try #require(fixture.snapshot.providers.first)
        provider.baseURL = "https://api.example.com/v1"
        let snapshot = RoutingSnapshot(
            generation: fixture.snapshot.generation,
            providers: [provider],
            mappings: fixture.snapshot.mappings,
            codex: fixture.snapshot.codex
        )
        let state = GatewayState(snapshot: snapshot)
        let mapping = try #require(snapshot.codex.defaultModel)
        let slug = CodexCatalog.slug(for: mapping, in: snapshot.providers)
        let cases = [
            AdmissionOrderingCase(
                path: "/v1/messages",
                body: #"{"model":"claude-opus-5","messages":[]}"#,
                expectedRewrite: .messages
            ),
            AdmissionOrderingCase(
                path: "/v1/responses",
                body: #"{"model":"\#(slug)","input":"hello"}"#,
                expectedRewrite: .responses
            ),
        ]

        for testCase in cases {
            let order = GatewayPipelineOrderRecorder()
            let admitter = SuspendedGatewayAdmitter(order: order)
            let serializer = RecordingGatewaySerializer()
            let transport = RecordingGatewayTransport(
                responses: [
                    HTTPClientResponse(
                        status: .ok,
                        headers: ["content-type": "application/json"],
                        body: .bytes(ByteBuffer(string: #"{"type":"message","content":[]}"#))
                    )
                ]
            )
            let app = Application(
                responder: GatewayResponder(
                    state: state,
                    transport: transport,
                    secretStore: fixture.secrets,
                    requiredAuthorityPort: nil,
                    trafficRecorder: order,
                    dependencies: GatewayResponderDependencies(
                        serializer: serializer,
                        admitter: admitter
                    )
                )
            )
            let request = Task {
                try await app.test(.router) { client in
                    try await client.execute(
                        uri: testCase.path,
                        method: .post,
                        body: ByteBuffer(string: testCase.body)
                    ).status
                }
            }

            try await admitter.waitUntilEntered()
            #expect(order.steps == [.routed, .admission])
            #expect(await admitter.requestCount == 1)
            #expect(serializer.rewriteCounts == .zero)
            #expect(await transport.requests.isEmpty)
            await admitter.resume()
            _ = try await valueWithinTimeout(
                request,
                description: "the admitted gateway request"
            )
            #expect(order.steps == [.routed, .admission, .upstreamRequest])
            #expect(await admitter.requestCount == 1)
            #expect(serializer.rewriteCounts == testCase.expectedRewrite.counts)
            #expect(await transport.requests.count == 1)
        }
    }
}

private struct AdmissionOrderingCase: Sendable {
    enum Rewrite: Sendable {
        case messages
        case responses

        var counts: RecordingGatewaySerializer.Counts {
            switch self {
            case .messages:
                .init(messages: 1, responses: 0)
            case .responses:
                .init(messages: 0, responses: 1)
            }
        }
    }

    let path: String
    let body: String
    let expectedRewrite: Rewrite
}

private actor SuspendedGatewayAdmitter: GatewayAdmitting {
    private let entered = AsyncTestGate()
    private let released = AsyncTestGate()
    private let order: GatewayPipelineOrderRecorder
    private(set) var requestCount = 0

    init(order: GatewayPipelineOrderRecorder) {
        self.order = order
    }

    func admit(state: GatewayState, request: GatewayRequestAdmission) async throws {
        _ = state
        _ = request
        requestCount += 1
        order.recordAdmission()
        await entered.open()
        try await released.wait()
    }

    func waitUntilEntered() async throws {
        try await entered.wait(description: "gateway admission")
    }

    func resume() async {
        await released.open()
    }
}

private enum GatewayPipelineStep: Equatable {
    case routed
    case admission
    case upstreamRequest
}

private final class GatewayPipelineOrderRecorder: TrafficRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSteps: [GatewayPipelineStep] = []

    var steps: [GatewayPipelineStep] {
        lock.withLock { storedSteps }
    }

    func record(eventID: UUID, action: TrafficAction) {
        _ = eventID
        switch action {
        case .routed:
            append(.routed)
        case .upstreamRequest:
            append(.upstreamRequest)
        default:
            break
        }
    }

    func recordAdmission() {
        append(.admission)
    }

    private func append(_ step: GatewayPipelineStep) {
        lock.withLock { storedSteps.append(step) }
    }
}

private final class RecordingGatewaySerializer: GatewaySerializing, @unchecked Sendable {
    struct Counts: Equatable, Sendable {
        var messages: Int
        var responses: Int

        static let zero = Counts(messages: 0, responses: 0)
    }

    private let lock = NSLock()
    private let live = LiveGatewaySerializer()
    private var counts = Counts.zero

    var rewriteCounts: Counts {
        lock.withLock { counts }
    }

    func encodeJSONObject(_ object: Any) throws -> Data {
        try live.encodeJSONObject(object)
    }

    func encodeCatalog(_ response: ClaudeCatalogResponse) throws -> Data {
        try live.encodeCatalog(response)
    }

    func rewriteMessage(_ body: Data, modelID: String) throws -> Data {
        lock.withLock { counts.messages += 1 }
        return try live.rewriteMessage(body, modelID: modelID)
    }

    func rewriteResponses(_ body: Data, modelID: String) throws -> Data {
        lock.withLock { counts.responses += 1 }
        return try live.rewriteResponses(body, modelID: modelID)
    }
}
