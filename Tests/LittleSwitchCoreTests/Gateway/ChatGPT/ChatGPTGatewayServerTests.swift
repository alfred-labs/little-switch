import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import NIOCore
import NIOPosix
import NIOSSL
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayServerTests {
    @Test func failedBindStopsAdmissionsForTheSecondaryListenerOnly() async throws {
        let occupied = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0).get()
        let port = try #require(occupied.localAddress?.port)
        let fixture = chatGPTGatewayFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM, authorityPEM: issued.authorityPEM, keyPEM: issued.keyPEM)
        let active = ChatGPTActiveTurns()
        let server = ChatGPTGatewayServer(
            state: fixture.state,
            secretStore: fixture.secrets,
            tlsIdentity: identity,
            transport: RecordingGatewayTransport(responses: []),
            history: try ChatGPTHistoryStore(),
            activeTurns: active,
            listenPort: port)
        await #expect(throws: (any Error).self) { try await server.start() }
        await #expect(throws: ChatGPTActiveTurns.Failure.stopped) {
            try await active.start(key: .init(owner: "owner", conversationID: "conversation")) {}
        }
        await server.stop()
        try await occupied.close().get()
        try await fixture.state.admit(client: .codex)
    }
    @Test func aCompletedConversationReopensAfterTheTLSListenerIsRecreated() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "ChatGPT/conversations.json")
        var provider = chatGPTGatewayFixture().snapshot.providers[0]
        provider.responsesWireOverride = .native
        let snapshot = RoutingSnapshot(generation: 1, providers: [provider], mappings: [:])
        let fixture = GatewayFixture(
            snapshot: snapshot,
            state: GatewayState(snapshot: snapshot),
            secrets: MemorySecretStore()
        )
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        var identifier: String?
        for pass in 0..<2 {
            let transport = RecordingGatewayTransport(
                responses: pass == 0 ? [try chatGPTProviderReply("Saved answer")] : []
            )
            let (server, port) = try await start(
                fixture: fixture,
                identity: identity,
                history: ChatGPTHistoryStore(fileURL: file),
                transport: transport
            )
            var tls = TLSConfiguration.makeClientConfiguration()
            tls.trustRoots = .certificates([identity.authority])
            let client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: .init(tlsConfiguration: tls))
            do {
                let path = identifier.map { "/conversation/" + $0 } ?? "/f/conversation"
                var request = HTTPClientRequest(url: "https://localhost:\(port)/backend-api" + path)
                request.headers.add(name: "authorization", value: "Bearer synthetic-session")
                if identifier == nil {
                    request.method = .POST
                    request.headers.add(name: "content-type", value: "application/json")
                    request.body = .bytes(ByteBuffer(bytes: try chatGPTTurnBody(text: "Keep this synthetic turn")))
                }
                let response = try await client.execute(request, timeout: .seconds(5))
                #expect(response.status == .ok)
                let body = Data(try await response.body.collect(upTo: 1_048_576).readableBytesView)
                if pass == 0 {
                    let events = try chatGPTNativeEvents(body)
                    identifier = try #require(events.first?["conversation_id"] as? String)
                    #expect(try #require(String(data: body, encoding: .utf8)).contains("finished_successfully"))
                } else {
                    let tree = try chatJSONObject(body)
                    #expect(tree["conversation_id"] as? String == identifier)
                    #expect(try #require(String(data: body, encoding: .utf8)).contains("Saved answer"))
                    #expect(await transport.requests.isEmpty)
                }
            } catch {
                try await client.shutdown()
                await server.stop()
                throw error
            }
            try await client.shutdown()
            await server.stop()
        }
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func rejectsInvalidPersistentHistoryBeforeCreatingTheConnection() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "conversations.json")
        try Data("not a history document".utf8).write(to: file)
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let fixture = chatGPTGatewayFixture()
        #expect(throws: ChatGPTHistoryError.invalidStorage) {
            try ChatGPTGatewayServer(
                state: fixture.state,
                secretStore: fixture.secrets,
                tlsIdentity: identity,
                historyFileURL: file
            )
        }
    }

    @Test func servesTheCatalogOverVerifiedLoopbackTLS() async throws {
        let fixture = chatGPTGatewayFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try ChatGPTLaunchTrust(directory: directory).prepare(
            inheriting: [:], authorityPEM: issued.authorityPEM)
        let authorityPath = try #require(environment["CODEX_CA_CERTIFICATE"])
        let (server, port) = try await start(fixture: fixture, identity: identity)
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.trustRoots = .file(authorityPath)
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(tlsConfiguration: configuration)
        )
        do {
            var request = HTTPClientRequest(url: "https://localhost:\(port)/backend-api/models")
            request.headers.add(name: "authorization", value: "Bearer synthetic-session")
            let response = try await client.execute(request, timeout: .seconds(5))
            #expect(response.status == .ok)
            let data = Data(try await response.body.collect(upTo: 1_048_576).readableBytesView)
            let object = try chatJSONObject(data)
            let models = try #require(object["models"] as? [[String: Any]])
            #expect(models.compactMap { $0["slug"] as? String } == ["native", "example:chat-model"])
            #expect(await server.isRunning)
        } catch {
            try await client.shutdown()
            await server.stop()
            throw error
        }
        try await client.shutdown()
        await server.stop()
        #expect(await !server.isRunning)
        try await fixture.state.admit(client: .codex)
    }

    private func start(
        fixture: GatewayFixture,
        identity: GatewayTLSIdentity,
        history: ChatGPTHistoryStore? = nil,
        transport suppliedTransport: RecordingGatewayTransport? = nil
    ) async throws -> (ChatGPTGatewayServer, Int) {
        for attempt in 0..<5 {
            let port = Int.random(in: 35_000..<55_000)
            let transport =
                suppliedTransport
                ?? RecordingGatewayTransport(responses: [
                    HTTPClientResponse(
                        status: .ok,
                        body: .bytes(ByteBuffer(string: #"{"models":[{"slug":"native","title":"Native"}]}"#))
                    )
                ])
            let server = ChatGPTGatewayServer(
                state: fixture.state,
                secretStore: fixture.secrets,
                tlsIdentity: identity,
                transport: transport,
                history: try history ?? ChatGPTHistoryStore(),
                listenPort: port
            )
            do {
                try await server.start()
                return (server, port)
            } catch {
                if attempt == 4 { throw error }
            }
        }
        throw GatewayServer.Error.stoppedBeforeReady
    }
}
