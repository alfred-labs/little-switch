import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

extension GatewayTests {
    @Test("The managed search endpoint answers Desktop's {q} contract")
    func managedWebSearchHappyPath() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body:
                    #"{"success":true,"data":{"web":[{"title":"Swift.org","#
                    + #""url":"https://swift.org/","#
                    + #""description":"The Swift project website"}]}}"#
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/web-search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"q":"Swift 6.2 release"}"#)
            )

            #expect(result.status == .ok)
            let object = try anthropicObject(data(result.body))
            let results = try #require(object["results"] as? [[String: Any]])
            try #require(results.count == 1)
            #expect(results[0]["title"] as? String == "Swift.org")
            #expect(results[0]["url"] as? String == "https://swift.org/")
            #expect(results[0]["snippet"] as? String == "The Swift project website")

            let requests = await transport.requests
            #expect(requests.map(\.url) == ["https://api.firecrawl.dev/v2/search"])
        }
    }

    @Test("A missing or blank query is rejected without touching the provider")
    func managedWebSearchRejectsMalformedQueries() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            for body in ["{}", #"{"q":"   "}"#, "not json"] {
                let result = try await client.execute(
                    uri: "/api/web-search",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(string: body)
                )
                #expect(result.status == .badRequest)
            }
            let requests = await transport.requests
            #expect(requests.isEmpty)
        }
    }

    @Test("The legacy search path keeps answering during the compat window")
    func managedWebSearchLegacyAlias() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body:
                    #"{"success":true,"data":{"web":[{"title":"Swift.org","#
                    + #""url":"https://swift.org/","#
                    + #""description":"The Swift project website"}]}}"#
            )
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/_little_switch/web_search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"q":"Swift 6.2 release"}"#)
            )

            #expect(result.status == .ok)
            let requests = await transport.requests
            #expect(requests.count == 1)
        }
    }

    @Test("A disabled search configuration reports unavailable")
    func managedWebSearchDisabled() async throws {
        let fixture = try makeWebSearchFixture(provider: .disabled)
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/web-search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"q":"anything"}"#)
            )

            #expect(result.status == .serviceUnavailable)
            let requests = await transport.requests
            #expect(requests.isEmpty)
        }
    }

    @Test("A provider failure surfaces as bad gateway")
    func managedWebSearchProviderFailure() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [
            response(status: .internalServerError, body: "{}")
        ])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/web-search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"q":"Swift 6.2 release"}"#)
            )

            #expect(result.status == .badGateway)
            let requests = await transport.requests
            #expect(requests.count == 1)
        }
    }

    @Test("An oversized body is refused before the provider is reached")
    func managedWebSearchOversizedBody() async throws {
        let fixture = try makeWebSearchFixture()
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(
            fixture: fixture,
            transport: transport,
            maximumRequestBytes: 32
        )

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/web-search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(
                    string: #"{"q":"a query far beyond the thirty-two byte bound"}"#
                )
            )

            #expect(result.status == .contentTooLarge)
            let requests = await transport.requests
            #expect(requests.isEmpty)
        }
    }
}

extension GatewayTests {
    @Test("A missing search key reports itself, not a provider failure")
    func managedWebSearchMissingCredential() async throws {
        // A fixture without the provider key stored.
        let base = try makeFixture()
        let snapshot = RoutingSnapshot(
            generation: base.snapshot.generation,
            providers: base.snapshot.providers,
            mappings: base.snapshot.mappings,
            webSearch: WebSearchConfiguration(provider: .firecrawl)
        )
        let fixture = GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: MemorySecretStore()
        )
        let transport = RecordingGatewayTransport(responses: [])
        let app = makeApplication(fixture: fixture, transport: transport)

        try await app.test(.router) { client in
            let result = try await client.execute(
                uri: "/api/web-search",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"q":"anything"}"#)
            )

            #expect(result.status == .serviceUnavailable)
            let object = try anthropicObject(data(result.body))
            let error = try #require(object["error"] as? [String: Any])
            #expect(error["message"] as? String == "Web search credential is missing")
        }
    }
}
