import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite("Upstream WebSocket compression", .timeLimit(.minutes(1)))
struct WebSocketCompressionTests {
    @Test("A negotiated compressed frame can expand beyond the codec's default 16 KiB")
    func inflatesLargeFrame() async throws {
        try await withServer(
            behavior: .init(
                headers: ["Sec-WebSocket-Extensions": "permessage-deflate"],
                initialFrames: [compressedFrame(), closeFrame()])
        ) { connection, _ in
            let messages = WebSocketMessageRecorder()
            let closed = try await connection.inbound.consume { await messages.append($0) }
            #expect(closed == .init(code: 1_000))
            #expect(await messages.values == [.text(String(repeating: "x", count: 40_000))])
        }
    }

    @Test("Offering compression does not require a peer to accept it")
    func peerDeclines() async throws {
        try await withServer(behavior: .init()) { connection, server in
            let messages = WebSocketMessageRecorder()
            async let closed = connection.inbound.consume { await messages.append($0) }
            try await connection.outbound.send(.text("uncompressed"))
            try await connection.outbound.close()
            _ = try await closed
            #expect(await messages.values == [.text("uncompressed")])
            let request = try #require(try await server.requests().first)
            #expect(request.headers["Sec-WebSocket-Extensions"] == ["permessage-deflate; client_max_window_bits"])
            #expect(try await server.frames().allSatisfy { !$0.rsv1 })
        }
    }

    @Test(
        "Compressed fragments preserve exact text, masking and message boundaries across reuse",
        arguments: [
            "permessage-deflate", "permessage-deflate; client_no_context_takeover; server_no_context_takeover",
            "permessage-deflate; server_max_window_bits=8",
        ])
    func compressedRoundTrips(header: String) async throws {
        try await withServer(
            behavior: .init(headers: ["Sec-WebSocket-Extensions": header], echoCompression: true)
        ) { connection, server in
            let messages = WebSocketMessageRecorder()
            let value = String(repeating: "{\"input\":\"é🍐synthetic\"}", count: 4_000)
            async let closed = connection.inbound.consume { await messages.append($0) }
            for _ in 0..<2 { try await connection.outbound.send(.text(value)) }
            try await connection.outbound.close()
            _ = try await closed
            #expect(await messages.values == [.text(value), .text(value)])
            let frames = try await server.frames().filter { $0.opcode != .connectionClose }
            #expect(frames.filter { $0.opcode == .text }.count == 2)
            #expect(frames.allSatisfy { $0.maskKey != nil && $0.rsv1 == ($0.opcode == .text) })
            #expect(frames.reduce(0) { $0 + $1.data.readableBytes } < value.utf8.count)
        }
    }

    @Test("The inbound message budget applies after decompression, including a single final frame")
    func inflatedMessageLimit() async throws {
        await #expect {
            try await withServer(
                behavior: .init(
                    headers: ["Sec-WebSocket-Extensions": "permessage-deflate"],
                    initialFrames: [compressedFrame()]),
                configuration: .init(maximumInboundMessageBytes: 32_768)
            ) { connection, _ in
                _ = try await connection.inbound.consume { _ in Issue.record("An oversized message escaped its limit") }
            }
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .messageTooLarge
        }
    }

    @Test("Compressed, uncompressed and empty text/binary messages coexist on a reused connection")
    func mixedMessages() async throws {
        let expected: [UpstreamWebSocketMessage] = [
            .text(String(repeating: "é🍐", count: 1_000)), .text(""), .text("plain"),
            .binary(Data()), .binary(Data([0, 255, 0])), .binary(Data(repeating: 255, count: 20_000)),
            .text("after binary"),
        ]
        try await withServer(
            behavior: .init(headers: ["Sec-WebSocket-Extensions": "permessage-deflate"], echoCompression: true)
        ) { connection, _ in
            let messages = WebSocketMessageRecorder()
            async let closed = connection.inbound.consume { await messages.append($0) }
            for message in expected { try await connection.outbound.send(message) }
            try await connection.outbound.close()
            _ = try await closed
            #expect(await messages.values == expected)
        }
    }

    // Independent raw-deflate fixture: 40,000 ASCII x bytes, Z_SYNC_FLUSH trailer removed.
    static let compressedBytes: [UInt8] = [
        236, 193, 49, 1, 0, 0, 0, 194, 160, 218, 139, 239, 101, 11, 160,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 27, 0,
    ]

    private func compressedFrame() -> WebSocketFrame {
        .init(fin: true, rsv1: true, opcode: .text, data: ByteBuffer(bytes: Self.compressedBytes))
    }

    private func closeFrame() -> WebSocketFrame {
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt16(1_000))
        return .init(fin: true, opcode: .connectionClose, data: buffer)
    }

    func withServer(
        behavior: WebSocketTestServer.Behavior,
        configuration: UpstreamWebSocketConfiguration = .init(),
        operation: @escaping @Sendable (UpstreamWebSocketConnection, WebSocketTestServer) async throws -> Void
    ) async throws {
        let server = try await WebSocketTestServer.start(behavior: behavior)
        let transport = try NIOUpstreamWebSocketTransport(configuration: configuration)
        do {
            let request = try UpstreamWebSocketRequest(
                url: #require(URL(string: "ws://127.0.0.1:\(server.port)/responses")))
            try await transport.withConnection(request) { try await operation($0, server) }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }
}
