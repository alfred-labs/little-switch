import AsyncHTTPClient
import Foundation
import NIOSSL
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring shared HTTP and HTTPS listener")
struct MonitoringDualProtocolTests {
    @Test("Both protocols expose the same metrics and logs, with a verified TLS chain")
    func sharedListener() async throws {
        let fixture = try GatewayTests().makeFixture()
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM,
            authorityPEM: issued.authorityPEM,
            keyPEM: issued.keyPEM
        )
        let store = MonitoringStore()
        _ = await store.markTest()
        let monitoring = GatewayMonitoring(store: store) { .init(exposeLogs: true) }
        let (server, port) = try await startServer(
            state: fixture.state,
            secrets: fixture.secrets,
            identity: identity,
            monitoring: monitoring
        )
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.trustRoots = .certificates([identity.authority])
        let client = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(tlsConfiguration: tls)
        )
        let exporter = OTLPHTTPTransport()
        do {
            for path in ["/metrics", "/logs"] {
                var bodies: [Data] = []
                for scheme in ["http", "https"] {
                    let response = try await client.execute(
                        HTTPClientRequest(url: "\(scheme)://localhost:\(port)\(path)"),
                        timeout: .seconds(5)
                    )
                    #expect(response.status == .ok)
                    #expect(response.headers.first(name: "Cache-Control") == "no-store")
                    let body = try await response.body.collect(upTo: 1_048_576)
                    bodies.append(Data(body.readableBytesView))
                }
                #expect(bodies.count == 2)
                #expect(bodies[0] == bodies[1])
            }
            let endpoint = try #require(URL(string: "https://localhost:\(port)/v1/metrics"))
            do {
                _ = try await exporter.send(to: endpoint, body: Data("{}".utf8), bearer: nil)
                Issue.record("The product exporter accepted an untrusted test authority")
            } catch {
                #expect(OTLPExportResponse.classify(error) == .permanent(.tls))
            }
            #expect(await store.snapshot().family(.requests) == nil)
        } catch {
            await exporter.shutdown()
            try await client.shutdown()
            await server.stop()
            throw error
        }
        await exporter.shutdown()
        try await client.shutdown()
        await server.stop()
    }

    private func startServer(
        state: GatewayState,
        secrets: any SecretStore,
        identity: GatewayTLSIdentity,
        monitoring: GatewayMonitoring
    ) async throws -> (GatewayServer, Int) {
        for attempt in 0..<5 {
            let port = Int.random(in: 35_000..<55_000)
            let server = GatewayServer(
                state: state,
                transport: RecordingGatewayTransport(responses: []),
                secretStore: secrets,
                listenPort: port,
                requiredAuthorityPort: nil,
                tlsIdentity: identity,
                monitoring: monitoring
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
