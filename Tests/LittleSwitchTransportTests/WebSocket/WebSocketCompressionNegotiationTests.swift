import NIOCore
import NIOHTTP1
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite("WebSocket compression negotiation", .timeLimit(.minutes(1)))
struct WebSocketCompressionNegotiationTests {
    @Test(
        "Valid negotiated parameters still decode provider messages",
        arguments: [
            "permessage-deflate; client_max_window_bits=9; server_max_window_bits=15",
            "permessage-deflate; server_max_window_bits=8; client_max_window_bits=9",
            "permessage-deflate; server_no_context_takeover; client_no_context_takeover",
            "permessage-deflate; server_max_window_bits=\"15\"; client_max_window_bits=\"12\"",
        ])
    func supportedParameters(header: String) async throws {
        let frame = WebSocketFrame(
            fin: true,
            rsv1: true,
            opcode: .text,
            data: ByteBuffer(bytes: WebSocketCompressionTests.compressedBytes))
        try await WebSocketCompressionTests().withServer(
            behavior: .init(headers: ["Sec-WebSocket-Extensions": header], initialFrames: [frame])
        ) { connection, _ in
            let messages = WebSocketMessageRecorder()
            let closed = try await connection.inbound.consume {
                await messages.append($0)
                try await connection.outbound.close()
            }
            #expect(closed.code == 1_000)
            #expect(await messages.values == [.text(String(repeating: "x", count: 40_000))])
        }
    }

    @Test(
        "Invalid, duplicate or unsolicited extension parameters never enter the operation",
        arguments: [
            "", "unknown", "permessage-deflate, unknown", "permessage-deflate, permessage-deflate",
            "permessage-deflate; unknown", "permessage-deflate; client_max_window_bits",
            "permessage-deflate; client_max_window_bits=8", "permessage-deflate; server_max_window_bits=16",
            "permessage-deflate; server_max_window_bits=7", "permessage-deflate; client_max_window_bits=16",
            "permessage-deflate; server_max_window_bits=garbage", "permessage-deflate; client_max_window_bits=+15",
            "permessage-deflate; client_no_context_takeover=true", "permessage-deflate; server_no_context_takeover=0",
            "permessage-deflate; server_no_context_takeover; server_no_context_takeover",
            "permessage-deflate; client_max_window_bits=10; client_max_window_bits=15",
            "permessage-deflate;", "permessage-deflate; ; server_max_window_bits=15",
        ])
    func invalidParameters(header: String) async throws {
        await #expect {
            try await WebSocketCompressionTests().withServer(
                behavior: .init(headers: ["Sec-WebSocket-Extensions": header])
            ) { _, _ in
                Issue.record("An invalid compression negotiation entered the operation")
            }
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .invalidUpgrade
        }
    }

    @Test("Duplicate extension headers are rejected even when each is individually supported")
    func duplicateHeaders() async throws {
        let headers = HTTPHeaders([
            ("Sec-WebSocket-Extensions", "permessage-deflate"),
            ("sec-websocket-extensions", "permessage-deflate"),
        ])
        await #expect {
            try await WebSocketCompressionTests().withServer(behavior: .init(headers: headers)) { _, _ in
                Issue.record("Duplicate extension headers entered the operation")
            }
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .invalidUpgrade
        }
    }
}
