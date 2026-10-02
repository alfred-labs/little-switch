import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite("Deflate stream boundary regressions", .timeLimit(.minutes(1)))
struct WebSocketDeflateRegressionTests {
    @Test("Invalid inflater configuration reports an error without destroying C state twice")
    func invalidInflaterConfiguration() throws {
        #expect {
            _ = try WebSocketInflater(maximumBytes: 8, windowBits: 16, noContextTakeover: false)
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .invalidConfiguration
        }
    }

    @Test("A final DEFLATE block does not discard the following message", arguments: [false, true])
    func finalBlockReuse(noContextTakeover: Bool) async throws {
        // RFC 7692 section 7.2.3.4: a BFINAL=1 block and the required empty-block header.
        let final: [UInt8] = [0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x00]
        let next: [UInt8] = [0xf2, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00]
        try await expectMessages(
            frames: [frame(final), frame(next)],
            header: noContextTakeover ? "permessage-deflate; server_no_context_takeover" : "permessage-deflate",
            expected: [.text("Hello"), .text("Hello")])
    }

    @Test("Every final DEFLATE block in one message contributes its payload", arguments: [false, true])
    func multipleFinalBlocks(fragmented: Bool) async throws {
        let payload: [UInt8] = [
            0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00,
            0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x00,
        ]
        let frames: [WebSocketFrame] =
            fragmented
            ? [
                .init(fin: false, rsv1: true, opcode: .text, data: ByteBuffer(bytes: payload.prefix(7))),
                .init(fin: true, opcode: .continuation, data: ByteBuffer(bytes: payload.dropFirst(7))),
            ] : [frame(payload)]
        try await expectMessages(frames: frames, expected: [.text("HelloHello")])
    }

    @Test("Context takeover retains the dictionary across a final DEFLATE block")
    func finalBlockDictionary() async throws {
        // The second RFC fixture references the first message's sliding window.
        let first: [UInt8] = [0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x00]
        let next: [UInt8] = [0xf2, 0x00, 0x11, 0x00, 0x00]
        try await expectMessages(frames: [frame(first), frame(next)], expected: [.text("Hello"), .text("Hello")])
    }

    @Test("An exact decoded limit succeeds while one extra byte fails", arguments: [false, true])
    func exactLimit(oversized: Bool) async throws {
        // Independent raw-zlib fixtures for eight and nine ASCII x bytes.
        let payload: [UInt8] = oversized ? [0xaa, 0xa8, 0x80, 0x02, 0x00, 0x00] : [0xaa, 0xa8, 0x80, 0x00, 0x00, 0x00]
        if oversized {
            await #expect {
                try await expectMessages(frames: [frame(payload)], maximumBytes: 8, expected: [])
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .messageTooLarge
            }
        } else {
            try await expectMessages(frames: [frame(payload)], maximumBytes: 8, expected: [.text("xxxxxxxx")])
        }
    }

    @Test("A final compressed frame requires the stripped empty-block boundary", arguments: [[], [0x00, 0x00]])
    func truncatedPayload(payload: [UInt8]) async throws {
        await #expect {
            try await expectMessages(frames: [frame(payload)], expected: [])
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .protocolViolation
        }
    }

    @Test("The compressed representation of an empty message remains valid")
    func emptyCompressedMessage() async throws {
        try await expectMessages(frames: [frame([0x00])], expected: [.text("")])
    }

    private func frame(_ payload: [UInt8]) -> WebSocketFrame {
        .init(fin: true, rsv1: true, opcode: .text, data: ByteBuffer(bytes: payload))
    }

    private func expectMessages(
        frames: [WebSocketFrame],
        header: String = "permessage-deflate",
        maximumBytes: Int = 8 * 1_024 * 1_024,
        expected: [UpstreamWebSocketMessage]
    ) async throws {
        var close = ByteBuffer()
        close.writeInteger(UInt16(1_000))
        try await WebSocketCompressionTests().withServer(
            behavior: .init(
                headers: ["Sec-WebSocket-Extensions": header],
                initialFrames: frames + [.init(fin: true, opcode: .connectionClose, data: close)]),
            configuration: .init(maximumInboundMessageBytes: maximumBytes)
        ) { connection, _ in
            let messages = WebSocketMessageRecorder()
            _ = try await connection.inbound.consume { await messages.append($0) }
            #expect(await messages.values == expected)
        }
    }
}
