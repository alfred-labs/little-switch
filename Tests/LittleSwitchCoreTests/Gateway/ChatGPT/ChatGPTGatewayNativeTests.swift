import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayNativeTests {
    @Test func nativeConditionalResponsePreservesNotModified() async throws {
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(status: .notModified, headers: ["etag": "same"])
        ])
        try await chatGPTApplication(fixture: chatGPTGatewayFixture(), transport: transport).test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/native-resource",
                method: .get,
                headers: [.ifNoneMatch: "same"]
            )
            #expect(response.status == .notModified)
            #expect(response.headers[.eTag] == "same")
        }
    }
    @Test func catalogPreservesNativeRowsAndAppendsExposedModels() async throws {
        let fixture = chatGPTGatewayFixture()
        let original = #"{"models":[{"slug":"native","title":"Native"}],"default_model_slug":"native","versions":[]}"#
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(status: .ok, headers: ["etag": "upstream"], body: .bytes(ByteBuffer(string: original)))
        ])
        try await chatGPTApplication(fixture: fixture, transport: transport).test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/models?iim=false",
                method: .get,
                headers: [.authorization: "Bearer synthetic-session", .ifNoneMatch: "stale"]
            )
            #expect(response.status == .ok)
            let object = try chatJSONObject(Data(response.body.readableBytesView))
            let models = try #require(object["models"] as? [[String: Any]])
            #expect(models.compactMap { $0["slug"] as? String } == ["native", "example:chat-model"])
            #expect(object["default_model_slug"] as? String == "native")
            #expect(response.headers[.eTag] == nil)
            #expect(response.headers[.cacheControl] == "no-store")
        }
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url == "https://chatgpt.com/backend-api/models?iim=false")
        #expect(requests.first?.headers["authorization"] == ["Bearer synthetic-session"])
        #expect(requests.first?.headers["if-none-match"].isEmpty == true)
    }

    @Test func nativeRequestsKeepBodyAndSessionOnOfficialOrigin() async throws {
        let fixture = chatGPTGatewayFixture()
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .accepted,
                headers: ["content-type": "application/json", "x-native": "preserved"],
                body: .bytes(ByteBuffer(string: #"{"accepted":true}"#))
            )
        ])
        let hidden = try #require(HTTPField.Name("x-connection-private"))
        try await chatGPTApplication(fixture: fixture, transport: transport).test(.router) { client in
            let response = try await client.execute(
                uri: "/backend-api/conversation/init",
                method: .post,
                headers: [
                    .authorization: "Bearer synthetic-session", .cookie: "synthetic-cookie=1",
                    .connection: "x-connection-private", hidden: "never-forward", .contentType: "application/json",
                ],
                body: ByteBuffer(string: #"{"requested_default_model":"native"}"#)
            )
            #expect(response.status == .accepted)
            #expect(String(buffer: response.body) == #"{"accepted":true}"#)
        }
        let request = try #require(await transport.requests.first)
        #expect(request.url == "https://chatgpt.com/backend-api/conversation/init")
        #expect(request.body == Data(#"{"requested_default_model":"native"}"#.utf8))
        #expect(request.headers["authorization"] == ["Bearer synthetic-session"])
        #expect(request.headers["cookie"] == ["synthetic-cookie=1"])
        #expect(request.headers["connection"].isEmpty)
        #expect(request.headers["x-connection-private"].isEmpty)
        #expect(request.headers["host"].isEmpty)
    }

    @Test func rejectsOtherOriginsAndPathsWithoutForwarding() async throws {
        let transport = RecordingGatewayTransport(responses: [])
        try await chatGPTApplication(fixture: chatGPTGatewayFixture(), transport: transport).test(.router) { client in
            let external = try await client.execute(
                uri: "/backend-api/models",
                method: .get,
                headers: [.origin: "https://example.invalid"]
            )
            #expect(external.status == .forbidden)
            let unknown = try await client.execute(uri: "/v1/responses", method: .post)
            #expect(unknown.status == .notFound)
        }
        #expect(await transport.requests.isEmpty)
    }
}

func chatGPTGatewayFixture() -> GatewayFixture {
    let provider = Provider(
        name: "Example",
        baseURL: "https://provider.invalid",
        authMode: .none,
        models: [DiscoveredModel(id: "chat-model")]
    )
    let snapshot = RoutingSnapshot(generation: 1, providers: [provider], mappings: [:])
    return GatewayFixture(snapshot: snapshot, state: GatewayState(snapshot: snapshot), secrets: MemorySecretStore())
}

func chatGPTApplication(
    fixture: GatewayFixture,
    transport: any UpstreamTransport
) -> Application<ChatGPTGatewayResponder> {
    Application(
        responder: ChatGPTGatewayResponder(
            state: fixture.state,
            transport: transport,
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil
        )
    )
}
