import Foundation
import LittleSwitchTransport
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Native compaction recovery")
struct GatewayNativeCompactionRecoveryTests {
    @Test(
        "Opaque history is summarized by a discovered native model before custom continuation",
        arguments: [false, true])
    func preservesOpaqueHistoryAndCustomSettings(hasTrigger: Bool) async throws {
        let transport = RecordingGatewayTransport(
            responses: [
                response(status: .ok, body: Self.nativeCatalog),
                response(status: .ok, body: compactionSummaryResponse()),
            ],
            routeStatuses: ["/models": 405]
        )
        let responder = try makeResponder(transport: transport)
        let original = try request(hasTrigger: hasTrigger)
        let recovered = try await responder.recoverNativeCompaction(
            body: original,
            incomingHeaders: [
                "authorization": "Bearer synthetic-openai", "chatgpt-account-id": "synthetic-account",
                "user-agent": "codex_cli_rs/0.140.0-beta.1 (macOS)", "x-api-key": "synthetic-custom",
            ],
            eventID: UUID()
        )
        var expected = try object(original)
        let originalInput = try #require(expected["input"] as? [[String: Any]])
        let payload: [String: Any] = [
            "type": "little_switch_compaction", "version": 1,
            "summary": "Continue the implementation; the file was read.",
            "retained": Array(originalInput.prefix(2)),
        ]
        expected["input"] =
            [
                ["type": "compaction", "encrypted_content": try ResponsesCompactionJSON.text(payload)]
            ] + (hasTrigger ? [["type": "compaction_trigger", "tag": "original"]] : [])
        #expect(try canonical(recovered) == canonical(JSONSerialization.data(withJSONObject: expected)))

        let requests = await transport.requests
        #expect(requests.count == 2)
        let discovery = try #require(requests.first)
        #expect(discovery.url == "https://chatgpt.com/backend-api/codex/models?client_version=0.140.0")
        #expect(discovery.body.isEmpty)
        for request in requests {
            #expect(request.headers["authorization"] == ["Bearer synthetic-openai"])
            #expect(request.headers["x-api-key"].isEmpty)
        }
        let summary = try object(try #require(requests.last).body)
        #expect(summary["model"] as? String == "native-preferred")
        #expect(summary["stream"] as? Bool == true)
        #expect(summary["temperature"] == nil)
        #expect(summary["reasoning"] == nil)
        let input = try #require(summary["input"] as? [[String: Any]])
        #expect(input.contains { $0["encrypted_content"] as? String == "opaque-native-checkpoint" })
        #expect(!input.contains { $0["type"] as? String == "compaction_trigger" })
    }

    @Test("API model discovery skips specialized artifacts and preserves catalog priority")
    func selectsAccessibleAPIModel() async throws {
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body:
                    #"""
                    {"data":[
                        {"id":"text-embedding-3-large","priority":0},
                        {"id":"gpt-5-audio","priority":1},
                        {"id":"gpt-5-codex","priority":3},
                        {"id":"gpt-5.6-sol","priority":2}
                    ]}
                    """#
            ),
            response(status: .ok, body: compactionSummaryResponse()),
        ])
        _ = try await makeResponder(transport: transport).recoverNativeCompaction(
            body: request(), incomingHeaders: ["authorization": "Bearer synthetic-api"], eventID: UUID()
        )
        let requests = await transport.requests
        #expect(try #require(requests.first).url == "https://api.openai.com/v1/models")
        #expect(try object(try #require(requests.last).body)["model"] as? String == "gpt-5.6-sol")
    }

    @Test(
        "Missing or sentinel authentication never starts discovery",
        arguments: [
            nil, "", "Basic synthetic", "Bearer ", "Bearer little-switch-local-codex",
            "bearer LITTLE-SWITCH-LOCAL-CODEX",
        ] as [String?])
    func requiresNativeAuthentication(authorization: String?) async throws {
        let transport = RecordingGatewayTransport(responses: [])
        let responder = try makeResponder(transport: transport)
        var headers = HTTPHeaders()
        if let authorization { headers.add(name: "authorization", value: authorization) }
        await #expect(throws: GatewayNativeCompactionRecoveryError.needsAuthentication) {
            try await responder.recoverNativeCompaction(body: request(), incomingHeaders: headers, eventID: UUID())
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(
        "Invalid discovery does not discard opaque state",
        arguments: [
            "not-json", "[]", #"{"data":[]}"#, #"{"data":[{"id":"text-embedding-3-large"}]}"#,
            #"{"data":[{"id":"gpt-latest"}]}"#, #"{"data":[{"id":"o"}]}"#,
        ])
    func rejectsInvalidDiscovery(catalog: String) async throws {
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: catalog)])
        let responder = try makeResponder(transport: transport)
        await #expect(throws: GatewayNativeCompactionRecoveryError.invalidDiscovery) {
            try await responder.recoverNativeCompaction(
                body: request(), incomingHeaders: ["authorization": "Bearer synthetic"], eventID: UUID()
            )
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("A discovery failure preserves the upstream status and error body")
    func preservesDiscoveryFailure() async throws {
        let transport = RecordingGatewayTransport(responses: [response(status: .tooManyRequests, body: "rate limited")])
        do {
            _ = try await makeResponder(transport: transport).recoverNativeCompaction(
                body: request(), incomingHeaders: ["authorization": "Bearer synthetic"], eventID: UUID()
            )
            Issue.record("Recovery unexpectedly succeeded")
        } catch let failure as CompactionUpstreamFailure {
            #expect(failure.response.status == .tooManyRequests)
            #expect(failure.body == Data("rate limited".utf8))
        }
    }

    @Test("Discovery body failures remain bounded and typed", arguments: [false, true])
    func boundsDiscoveryBody(upstreamFailure: Bool) async throws {
        let transport = RecordingGatewayTransport(responses: [
            response(status: upstreamFailure ? .forbidden : .ok, body: String(repeating: "x", count: 64))
        ])
        let responder = try makeResponder(transport: transport, maximumErrorBytes: 8)
        do {
            _ = try await responder.recoverNativeCompaction(
                body: request(), incomingHeaders: ["authorization": "Bearer synthetic"], eventID: UUID()
            )
            Issue.record("Oversized discovery unexpectedly succeeded")
        } catch let error as GatewayNativeCompactionRecoveryError {
            #expect(!upstreamFailure)
            #expect(error == .invalidDiscovery)
        } catch let failure as CompactionUpstreamFailure {
            #expect(upstreamFailure)
            #expect(failure.response.status == .forbidden)
            #expect(failure.body.isEmpty)
        }
    }

    @Test("Cancellation while reading discovery prevents the summary request")
    func cancelsDiscoveryBody() async throws {
        let transport = RecordingGatewayTransport(responses: [failingResponse(error: CancellationError())])
        let responder = try makeResponder(transport: transport)
        await #expect(throws: CancellationError.self) {
            try await responder.recoverNativeCompaction(
                body: request(), incomingHeaders: ["authorization": "Bearer synthetic"], eventID: UUID()
            )
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(
        "Invalid or absent Codex versions never become query parameters",
        arguments: [
            "", "other/1.2.3", "codex/invalid", "codex/1..3", "codex/١.2.3", "codex/1.2.3/extra",
        ])
    func ignoresInvalidClientVersions(userAgent: String) async throws {
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: Self.nativeCatalog), response(status: .ok, body: compactionSummaryResponse()),
        ])
        _ = try await makeResponder(transport: transport).recoverNativeCompaction(
            body: request(),
            incomingHeaders: [
                "authorization": "Bearer synthetic", "chatgpt-account-id": "account", "user-agent": userAgent,
            ], eventID: UUID()
        )
        #expect(try #require(await transport.requests.first).url == "https://chatgpt.com/backend-api/codex/models")
    }

    @Test(
        "Model selection admits coding and reasoning families without inventing an alias",
        arguments: [
            "codex-mini-latest", "o3", "gpt-5.6-sol",
        ])
    func selectsAPIFamilies(model: String) async throws {
        let catalog = try ResponsesCompactionJSON.text([
            "data": [
                ["id": "gpt-3.5-turbo"], ["id": "other-artifact"], ["id": ""],
                ["id": "gpt-5-images-only", "input_modalities": ["image"]],
                ["id": model, "priority": true], ["id": "gpt-5-other"],
            ]
        ])
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: catalog), response(status: .ok, body: compactionSummaryResponse()),
        ])
        _ = try await makeResponder(transport: transport).recoverNativeCompaction(
            body: request(), incomingHeaders: ["authorization": "Bearer synthetic"], eventID: UUID()
        )
        #expect(try object(try #require(await transport.requests.last).body)["model"] as? String == model)
    }

    @Test(
        "Malformed recovery requests never reach discovery",
        arguments: [
            #"{"input":"message"}"#, #"{"input":[{"type":"message","role":"user","content":"hello"}]}"#,
            #"{"input":[{"type":"compaction_trigger"},{"type":"compaction","encrypted_content":"opaque"}]}"#,
        ])
    func rejectsInvalidRequests(body: String) async throws {
        let transport = RecordingGatewayTransport(responses: [])
        let responder = try makeResponder(transport: transport)
        await #expect(throws: ResponsesCompactionError.invalidRequest) {
            try await responder.recoverNativeCompaction(body: Data(body.utf8), incomingHeaders: [:], eventID: UUID())
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("The request limit applies before discovery and to the recovered wrapper", arguments: [false, true])
    func boundsRecoveryPayload(oversizedInput: Bool) async throws {
        let summary = compactionSummaryResponse().replacingOccurrences(
            of: "Continue the implementation; the file was read.", with: String(repeating: "s", count: 8_000)
        )
        let transport = RecordingGatewayTransport(responses: [
            response(status: .ok, body: Self.nativeCatalog), response(status: .ok, body: summary),
        ])
        let responder = try makeResponder(transport: transport, maximumRequestBytes: oversizedInput ? 1 : 6_000)
        await #expect(throws: ResponsesCompactionError.invalidRequest) {
            try await responder.recoverNativeCompaction(
                body: request(),
                incomingHeaders: ["authorization": "Bearer synthetic", "chatgpt-account-id": "account"],
                eventID: UUID()
            )
        }
        #expect(await transport.requests.count == (oversizedInput ? 0 : 2))
    }

    @Test("A serialized request without a compaction plan is rejected")
    func rejectsMissingSerializedPlan() async throws {
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: Self.nativeCatalog)])
        let responder = try makeResponder(transport: transport, serializer: MissingRecoveryPlanSerializer())
        await #expect(throws: ResponsesCompactionError.invalidRequest) {
            try await responder.recoverNativeCompaction(
                body: request(),
                incomingHeaders: ["authorization": "Bearer synthetic", "chatgpt-account-id": "account"],
                eventID: UUID()
            )
        }
        #expect(await transport.requests.count == 1)
    }

    private static let nativeCatalog = #"""
        {"models":[
            {"slug":"native-lower","visibility":"list","priority":3},
            {"slug":"native-hidden","visibility":"hide","priority":0},
            {"slug":"native-preferred","visibility":"list","priority":1,"input_modalities":["text","image"]}
        ]}
        """#

    private func makeResponder(
        transport: any UpstreamTransport,
        maximumRequestBytes: Int = 64 * 1_024 * 1_024,
        maximumErrorBytes: Int = 8 * 1_024 * 1_024,
        serializer: any GatewaySerializing = LiveGatewaySerializer()
    ) throws -> GatewayResponder {
        let fixture = try GatewayTests().makeFixture()
        return GatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            maximumRequestBytes: maximumRequestBytes,
            maximumErrorBytes: maximumErrorBytes,
            requiredAuthorityPort: nil,
            dependencies: GatewayResponderDependencies(serializer: serializer)
        )
    }

    private func request(hasTrigger: Bool = false) throws -> Data {
        let input: [[String: Any]] =
            [
                ["type": "compaction", "encrypted_content": "opaque-native-checkpoint"],
                [
                    "type": "reasoning", "id": "rs_original", "encrypted_content": "opaque-native-reasoning",
                    "summary": [],
                ],
                ["type": "message", "role": "user", "content": "Continue the implementation."],
            ] + (hasTrigger ? [["type": "compaction_trigger", "tag": "original"]] : [])
        return try JSONSerialization.data(withJSONObject: [
            "model": "z.ai/glm-5.2", "stream": hasTrigger, "input": input,
            "temperature": 0.3, "reasoning": ["effort": "high"], "metadata": ["correlation": "synthetic"],
            "instructions": "Preserve the implementation context.",
        ])
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonical(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: object(data), options: [.sortedKeys])
    }
}

private struct MissingRecoveryPlanSerializer: GatewaySerializing {
    func encodeJSONObject(_ object: Any) throws -> Data { Data("{}".utf8) }
    func encodeCatalog(_ response: ClaudeCatalogResponse) throws -> Data {
        try LiveGatewaySerializer().encodeCatalog(response)
    }
    func rewriteMessage(_ body: Data, modelID: String) throws -> Data {
        try LiveGatewaySerializer().rewriteMessage(body, modelID: modelID)
    }
    func rewriteResponses(_ body: Data, modelID: String) throws -> Data {
        try LiveGatewaySerializer().rewriteResponses(body, modelID: modelID)
    }
}
