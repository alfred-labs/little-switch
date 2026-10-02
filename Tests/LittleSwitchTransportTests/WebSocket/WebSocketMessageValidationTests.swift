import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketMessageValidationTests {
    @Test func assemblesUTF8AcrossFramesAndKeepsBinaryBytes() async throws {
        let frames: [WebSocketFrame] = [
            .init(fin: false, opcode: .text, data: ByteBuffer(bytes: [0xF0, 0x9F])),
            .init(fin: true, opcode: .ping, data: ByteBuffer(string: "between")),
            .init(fin: true, opcode: .continuation, data: ByteBuffer(bytes: [0x98, 0x80])),
            .init(fin: true, opcode: .binary, data: ByteBuffer(bytes: [0, 255, 0])),
            Self.closeFrame(code: 1_013, reason: "retry later"),
        ]
        let messages = WebSocketMessageRecorder()
        try await Self.withPeer(frames: frames) { connection in
            let close = try await connection.inbound.consume { await messages.append($0) }
            #expect(close == .init(code: 1_013))
        }
        #expect(await messages.values == [.text("😀"), .binary(Data([0, 255, 0]))])
    }

    @Test(arguments: [
        [WebSocketFrame(fin: true, opcode: .text, data: ByteBuffer(bytes: [0xC0, 0xAF]))],
        [WebSocketFrame(fin: true, opcode: .continuation, data: ByteBuffer(string: "orphan"))],
        [
            WebSocketFrame(fin: false, opcode: .text, data: ByteBuffer(string: "first")),
            WebSocketFrame(fin: true, opcode: .text, data: ByteBuffer(string: "second")),
        ],
        [WebSocketFrame(fin: true, opcode: .connectionClose, data: ByteBuffer(bytes: [0]))],
        [Self.closeFrame(code: 1_005)],
        [WebSocketFrame(fin: true, opcode: .connectionClose, data: ByteBuffer(bytes: [3, 232, 255]))],
        [WebSocketFrame(fin: true, rsv1: true, opcode: .text, data: ByteBuffer(string: "reserved"))],
        [WebSocketFrame(fin: true, opcode: .text, maskKey: .init([1, 2, 3, 4]), data: ByteBuffer(string: "masked"))],
    ])
    func rejectsInvalidMessages(frames: [WebSocketFrame]) async throws {
        await #expect {
            try await Self.withPeer(frames: frames) { connection in
                _ = try await connection.inbound.consume { _ in
                    Issue.record("An invalid message reached the application")
                }
            }
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .protocolViolation
        }
    }

    @Test(arguments: [false, true])
    func boundsSingleAndFragmentedMessages(fragmented: Bool) async throws {
        let frames: [WebSocketFrame] =
            fragmented
            ? [
                .init(fin: false, opcode: .binary, data: ByteBuffer(bytes: [1, 2, 3])),
                .init(fin: true, opcode: .continuation, data: ByteBuffer(bytes: [4, 5, 6])),
            ]
            : [.init(fin: true, opcode: .binary, data: ByteBuffer(bytes: [1, 2, 3, 4, 5, 6]))]
        await #expect {
            try await Self.withPeer(frames: frames, maximumBytes: 4) { connection in
                _ = try await connection.inbound.consume { _ in
                    Issue.record("An oversized message reached the application")
                }
            }
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .messageTooLarge
        }
    }

    private static func closeFrame(code: UInt16, reason: String = "") -> WebSocketFrame {
        var data = ByteBuffer()
        data.writeInteger(code)
        data.writeString(reason)
        return .init(fin: true, opcode: .connectionClose, data: data)
    }

    private static func withPeer(
        frames: [WebSocketFrame],
        maximumBytes: Int = 1_024,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        let server = try await WebSocketTestServer.start(behavior: .init(initialFrames: frames))
        let transport = try NIOUpstreamWebSocketTransport(
            configuration: .init(
                closeTimeout: .milliseconds(100), maximumInboundMessageBytes: maximumBytes))
        do {
            let url = try #require(URL(string: "ws://127.0.0.1:\(server.port)/responses"))
            try await transport.withConnection(UpstreamWebSocketRequest(url: url), operation: operation)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }
}
