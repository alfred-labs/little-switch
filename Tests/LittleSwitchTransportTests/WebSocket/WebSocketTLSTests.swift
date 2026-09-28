import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketTLSTests {
    @Test(arguments: ["localhost", "127.0.0.1"])
    func acceptsVerifiedTLS(host: String) async throws {
        let contexts = try WebSocketTLSFixture.contexts()
        var close = ByteBuffer()
        close.writeInteger(UInt16(1_000))
        let server = try await WebSocketTestServer.start(
            behavior: .init(initialFrames: [
                .init(fin: true, opcode: .binary, data: ByteBuffer(bytes: [0, 1, 255])),
                .init(fin: true, opcode: .connectionClose, data: close),
            ]), tlsContext: contexts.server)
        let transport = try NIOUpstreamWebSocketTransport(tlsContext: contexts.client)
        let messages = WebSocketMessageRecorder()
        do {
            let url = try #require(URL(string: "wss://\(host):\(server.port)/v1/responses"))
            try await transport.withConnection(UpstreamWebSocketRequest(url: url)) { connection in
                let peer = try await connection.inbound.consume { await messages.append($0) }
                #expect(peer == .init(code: 1_000, reason: nil))
            }
            #expect(await messages.values == [.binary(Data([0, 1, 255]))])
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test(arguments: [false, true])
    func rejectsUntrustedOrWrongHostname(wrongHostname: Bool) async throws {
        let contexts = try WebSocketTLSFixture.contexts(wrongHostname: wrongHostname)
        let server = try await WebSocketTestServer.start(tlsContext: contexts.server)
        let transport =
            try wrongHostname
            ? NIOUpstreamWebSocketTransport(tlsContext: contexts.client)
            : NIOUpstreamWebSocketTransport()
        do {
            let url = try #require(URL(string: "wss://localhost:\(server.port)/v1/responses"))
            do {
                try await transport.withConnection(UpstreamWebSocketRequest(url: url)) { _ in
                    Issue.record("A failed TLS verification must not enter the connection operation")
                }
                Issue.record("TLS verification unexpectedly succeeded")
            } catch let failure as UpstreamWebSocketFailure {
                #expect(failure.kind == .tlsFailed)
                #expect(failure.response == nil)
            }
            #expect(try await server.requests().isEmpty)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func closeDeadlineAlsoBoundsAnUnresponsiveTLSShutdown() async throws {
        let contexts = try WebSocketTLSFixture.contexts()
        let server = try await WebSocketTestServer.start(
            behavior: .init(acknowledgeClose: false, stopReadingAfterUpgrade: true), tlsContext: contexts.server)
        let transport = try NIOUpstreamWebSocketTransport(
            configuration: .init(closeTimeout: .milliseconds(50)), tlsContext: contexts.client)
        let started = ContinuousClock.now
        do {
            let url = try #require(URL(string: "wss://localhost:\(server.port)/responses"))
            await #expect {
                try await transport.withConnection(UpstreamWebSocketRequest(url: url)) { _ in }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .closeTimedOut
            }
            #expect(started.duration(to: .now) < .seconds(2))
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }
}
