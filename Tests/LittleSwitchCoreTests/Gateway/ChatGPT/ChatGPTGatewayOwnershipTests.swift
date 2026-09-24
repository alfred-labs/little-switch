import AsyncHTTPClient
import LittleSwitchTransport
import Testing

@testable import LittleSwitchCore

struct ChatGPTGatewayOwnershipTests {
    @Test func stopDrainsConcurrentStartupBeforeReturning() async throws {
        let transport = ChatGPTOwnedTransport(suspend: true)
        let server = try makeServer(transport: transport)
        let startup = Task { try await server.start() }
        startup.cancel()
        do {
            try await transport.entered.wait(description: "cancelled startup suspended in transport shutdown")
        } catch {
            await transport.release.open()
            _ = try? await startup.value
            throw error
        }
        let stop = Task { await server.stop() }
        do {
            let stopEntered: Bool = try await eventually(description: "stop owns shutdown") {
                do {
                    try await server.start()
                    return false
                } catch GatewayServer.Error.alreadyStarted {
                    return nil
                } catch GatewayServer.Error.stoppedBeforeReady {
                    return true
                }
            }
            try #require(stopEntered)
        } catch {
            await transport.release.open()
            await stop.value
            _ = try? await startup.value
            throw error
        }
        await transport.release.open()
        await stop.value
        #expect(await !server.isRunning)
        await #expect(throws: CancellationError.self) { try await startup.value }
        #expect(await !server.isRunning)
        #expect(await transport.shutdownCount == 1)
    }

    @Test func cancelledStartupClosesItsTransportAndRejectsASecondStart() async throws {
        let transport = ChatGPTOwnedTransport()
        let server = try makeServer(transport: transport)
        let startup = Task { try await server.start() }
        startup.cancel()
        await #expect(throws: CancellationError.self) { try await startup.value }
        await #expect(throws: GatewayServer.Error.alreadyStarted) { try await server.start() }
        await server.stop()
        #expect(await transport.shutdownCount == 1)
    }
    @Test func stoppingAConstructedListenerDisposesItsTransportOnce() async throws {
        let transport = ChatGPTOwnedTransport()
        let server = try makeServer(transport: transport)
        await server.stop()
        await server.stop()
        #expect(await transport.shutdownCount == 1)
        #expect(await !server.isRunning)
        await #expect(throws: GatewayServer.Error.stoppedBeforeReady) { try await server.start() }
    }

    @Test func concurrentStopsAwaitOneShutdownAndPreventLateStartup() async throws {
        let transport = ChatGPTOwnedTransport(suspend: true)
        let server = try makeServer(transport: transport)
        let first = Task { await server.stop() }
        do { try await transport.entered.wait(description: "owned transport shutdown") } catch {
            await transport.release.open()
            await first.value
            throw error
        }
        let second = Task { await server.stop() }
        await #expect(throws: GatewayServer.Error.stoppedBeforeReady) { try await server.start() }
        await transport.release.open()
        await first.value
        await second.value
        #expect(await transport.shutdownCount == 1)
    }

    private func makeServer(transport: ChatGPTOwnedTransport) throws -> ChatGPTGatewayServer {
        let issued = try GatewayTLSIdentityFactory.make()
        let identity = try GatewayTLSIdentity(
            certificatePEM: issued.certificatePEM, authorityPEM: issued.authorityPEM, keyPEM: issued.keyPEM)
        let fixture = chatGPTGatewayFixture()
        return ChatGPTGatewayServer(
            state: fixture.state,
            secretStore: fixture.secrets,
            tlsIdentity: identity,
            transport: transport,
            history: try ChatGPTHistoryStore(),
            listenPort: 0)
    }
}

private actor ChatGPTOwnedTransport: UpstreamTransport {
    let entered = AsyncTestGate()
    let release = AsyncTestGate()
    let suspend: Bool
    private(set) var shutdownCount = 0
    init(suspend: Bool = false) { self.suspend = suspend }
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        Issue.record("Disposal must not issue upstream requests")
        throw CancellationError()
    }
    func shutdown() async throws {
        shutdownCount += 1
        await entered.open()
        if suspend { try await release.wait() }
    }
}
