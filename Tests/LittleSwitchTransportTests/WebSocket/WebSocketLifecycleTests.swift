import Foundation
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketLifecycleTests {
    @Test func cancellationBeforeUpgradeClosesThePendingConnection() async throws {
        let server = try await WebSocketHTTPTestServer.start(reply: .init(sendHead: false))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(handshakeTimeout: .seconds(5)))
        do {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    do {
                        try await transport.withConnection(Self.request(port: server.port)) { _ in
                            Issue.record("A cancelled handshake must not start the operation")
                        }
                        return false
                    } catch is CancellationError {
                        return true
                    }
                }
                _ = try await server.request()
                group.cancelAll()
                #expect(try await group.next() == true)
            }
            try await server.waitForConnectionsToClose()
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func shutdownJoinsPendingConnectionsAndRejectsNewWork() async throws {
        let server = try await WebSocketHTTPTestServer.start(reply: .init(sendHead: false))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(handshakeTimeout: .seconds(5)))
        do {
            try await withThrowingTaskGroup(of: UpstreamWebSocketFailure.Kind?.self) { group in
                group.addTask {
                    do {
                        try await transport.withConnection(Self.request(port: server.port)) { _ in
                            Issue.record("Shutdown must not enter the operation")
                        }
                        return nil
                    } catch let error as UpstreamWebSocketFailure {
                        return error.kind
                    }
                }
                _ = try await server.request()
                async let first: Void = transport.shutdown()
                async let second: Void = transport.shutdown()
                _ = try await (first, second)
                #expect(try await group.next() == .transportShutDown)
            }
            try await server.waitForConnectionsToClose()
            await #expect {
                try await transport.withConnection(Self.request(port: server.port)) { _ in
                    Issue.record("A shut-down transport must reject new work")
                }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .transportShutDown
            }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func shutdownFromOperationFailsWithoutStoppingTheTransport() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport()
        do {
            try await transport.withConnection(Self.request(port: server.port)) { _ in
                await #expect {
                    try await transport.shutdown()
                } throws: { error in
                    (error as? UpstreamWebSocketFailure)?.kind == .shutdownFromConnection
                }
            }
            try await transport.withConnection(Self.request(port: server.port)) { _ in }
            #expect(try await server.requests().count == 2)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func expiredHandlesFailWithoutStartingASecondReader() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport()
        let retained = WebSocketConnectionHolder()
        do {
            try await transport.withConnection(Self.request(port: server.port)) { connection in
                await retained.set(connection)
            }
            let connection = try #require(await retained.value)
            await #expect {
                try await connection.outbound.send(.text("late"))
            } throws: { error in
                guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
                return failure.cause.kind == .connectionEnded && failure.submission == .notSubmitted
            }
            await #expect {
                try await connection.inbound.consume { _ in }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .connectionEnded
            }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func aPeerIgnoringCloseHasABoundedLifetime() async throws {
        let server = try await WebSocketTestServer.start(behavior: .init(acknowledgeClose: false))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(closeTimeout: .milliseconds(50)))
        do {
            await #expect {
                try await transport.withConnection(Self.request(port: server.port)) { _ in }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .closeTimedOut
            }
            #expect(try await server.frames().filter { $0.opcode == .connectionClose }.count == 1)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    private static func request(port: Int) throws -> UpstreamWebSocketRequest {
        try UpstreamWebSocketRequest(url: #require(URL(string: "ws://127.0.0.1:\(port)/responses")))
    }
}

private actor WebSocketConnectionHolder {
    private(set) var value: UpstreamWebSocketConnection?
    func set(_ value: UpstreamWebSocketConnection) { self.value = value }
}
