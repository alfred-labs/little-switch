import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketCloseRegressionTests {
    @Test func physicalCloseDisarmsTheDeadlineWhileTheOperationFinishes() async throws {
        var close = ByteBuffer()
        close.writeInteger(UInt16(1_000))
        let server = try await WebSocketTestServer.start(
            behavior: .init(initialFrames: [
                .init(fin: true, opcode: .connectionClose, data: close)
            ]))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(closeTimeout: .milliseconds(50)))
        do {
            try await transport.withConnection(Self.request(port: server.port)) { connection in
                let close = try await connection.inbound.consume { _ in }
                #expect(close == .init(code: 1_000, reason: nil))
                try await server.waitForConnectionsToClose()
                try await Task.sleep(for: .milliseconds(150))
            }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func aPeerCloseStopsTheCurrentMessageBeforeTheCloseAcknowledgement() async throws {
        let server = try await WebSocketTestServer.start(
            behavior: .init(
                echo: false, closeOnFirstDataFrame: true, keepConnectionOpenAfterClose: true))
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(outboundFragmentBytes: 1_024))
        do {
            try await transport.withConnection(Self.request(port: server.port)) { connection in
                async let closed = connection.inbound.consume { _ in }
                await #expect {
                    try await connection.outbound.send(.binary(Data(repeating: 42, count: 2 * 1_024 * 1_024)))
                } throws: { error in
                    guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
                    return failure.submission == .mayHaveBeenSubmitted && failure.cause.kind == .connectionClosing
                }
                let close = try await closed
                #expect(close == .init(code: 1_000, reason: nil))
            }
            try await server.waitForConnectionsToClose()
            let frames = try await server.frames()
            let firstClose = try #require(frames.firstIndex { $0.opcode == .connectionClose })
            #expect(!frames[..<firstClose].isEmpty)
            #expect(
                frames[(firstClose + 1)...].allSatisfy { frame in
                    frame.opcode != .text && frame.opcode != .binary && frame.opcode != .continuation
                })
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
