import Foundation
import HTTPTypes
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Managed model native egress boundary")
struct GatewayManagedModelNamespaceTests {
    @Test("An unavailable canonical model cannot leave through native egress", arguments: UnavailableModel.allCases)
    func unavailableCanonicalModel(reason: UnavailableModel) async throws {
        let helpers = GatewayTests()
        let original = try helpers.makeFixture()
        var snapshot = original.snapshot
        let model = "z.ai:glm-5.2"
        switch reason {
        case .removed:
            snapshot.providers = []
        case .excluded:
            snapshot.codex.excludedModels = [
                ModelMapping(providerID: snapshot.providers[0].id, modelID: "glm-5.2")
            ]
        case .ambiguous:
            snapshot.providers[0].models.append(snapshot.providers[0].models[0])
        }
        #expect(snapshot.resolveCodex(model: model) == nil)
        let fixture = GatewayFixture(
            snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: original.secrets)
        let transport = RecordingGatewayTransport(responses: [response(status: .accepted, body: "unexpected egress")])
        let app = helpers.makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json", .authorization: "Bearer synthetic-native-session"],
                body: ByteBuffer(string: #"{"model":"z.ai:glm-5.2","input":"Synthetic private context"}"#))
            #expect(result.status == .badRequest)
            #expect(String(buffer: result.body).contains("Unknown or invalid model"))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(
        "Canonical and malformed single-separator identifiers stay managed",
        arguments: ["local:qwen", "a%2fb:%43%3a%44", "local:%zz", "local:", ":qwen", ":", "old/provider/model"]
    )
    func reservedNamespace(model: String) throws {
        let body = try JSONSerialization.data(withJSONObject: ["model": model])
        #expect(!CodexNativePassthrough.isNativeRequest(body))
    }

    @Test("Native identifiers with several colons remain transparent")
    func nativeMultipleSeparators() async throws {
        let helpers = GatewayTests()
        let fixture = try helpers.makeFixture()
        let transport = RecordingGatewayTransport(responses: [response(status: .accepted, body: "native")])
        let app = helpers.makeApplication(fixture: fixture, transport: transport)
        let body = Data(#"{"model":"ft:gpt-4.1:organization:custom:id","input":"Synthetic native context"}"#.utf8)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/v1/responses",
                method: .post,
                headers: [.authorization: "Bearer synthetic-native-session"],
                body: ByteBuffer(bytes: body))
            #expect(result.status == .accepted)
        }
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url == "https://api.openai.com/v1/responses")
        #expect(requests.first?.body == body)
    }
}

enum UnavailableModel: CaseIterable, Sendable {
    case removed, excluded, ambiguous
}
