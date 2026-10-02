import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite("Compressed WebSocket boundaries", .timeLimit(.minutes(1)))
struct WebSocketCompressionBoundaryTests {
    @Test(
        "The decoded budget is cumulative across fragments and permits an exact-boundary message",
        arguments: [32_768, 40_000])
    func fragmentedBudget(maximumBytes: Int) async throws {
        let bytes = WebSocketCompressionTests.compressedBytes
        let frames: [WebSocketFrame] = [
            .init(fin: false, rsv1: true, opcode: .text, data: ByteBuffer(bytes: bytes.prefix(28))),
            .init(fin: true, opcode: .ping, data: ByteBuffer(string: "between")),
            .init(fin: true, opcode: .continuation, data: ByteBuffer(bytes: bytes.dropFirst(28))),
        ]
        let messages = WebSocketMessageRecorder()
        do {
            try await WebSocketCompressionTests().withServer(
                behavior: .init(headers: ["Sec-WebSocket-Extensions": "permessage-deflate"], initialFrames: frames),
                configuration: .init(maximumInboundMessageBytes: maximumBytes)
            ) { connection, server in
                _ = try await connection.inbound.consume {
                    await messages.append($0)
                    try await connection.outbound.close()
                }
                let pong = try #require(try await server.frames().first { $0.opcode == .pong })
                #expect(!pong.rsv1)
                #expect(String(buffer: pong.unmaskedData) == "between")
            }
            #expect(maximumBytes == 40_000)
            #expect(await messages.values == [.text(String(repeating: "x", count: 40_000))])
        } catch let error as UpstreamWebSocketFailure where maximumBytes < 40_000 {
            #expect(error.kind == .messageTooLarge)
            #expect(await messages.values.isEmpty)
        }
    }

    @Test(
        "Negotiating deflate never permits reserved control or continuation bits, corrupt data or masked server frames",
        arguments: [
            [WebSocketFrame(fin: true, rsv1: true, opcode: .ping, data: ByteBuffer())],
            [WebSocketFrame(fin: true, rsv1: true, opcode: .connectionClose, data: ByteBuffer())],
            [WebSocketFrame(fin: true, rsv2: true, opcode: .text, data: ByteBuffer(string: "invalid"))],
            [WebSocketFrame(fin: true, rsv3: true, opcode: .binary, data: ByteBuffer())],
            [WebSocketFrame(fin: true, rsv1: true, opcode: .text, data: ByteBuffer(bytes: [255, 255]))],
            [WebSocketFrame(fin: true, rsv1: true, opcode: .text, maskKey: .init([1, 2, 3, 4]), data: ByteBuffer())],
            [
                WebSocketFrame(fin: false, opcode: .text, data: ByteBuffer(string: "prefix")),
                WebSocketFrame(fin: true, rsv1: true, opcode: .continuation, data: ByteBuffer()),
            ],
        ])
    func malformedFrames(frames: [WebSocketFrame]) async throws {
        await #expect {
            try await WebSocketCompressionTests().withServer(
                behavior: .init(headers: ["Sec-WebSocket-Extensions": "permessage-deflate"], initialFrames: frames)
            ) { connection, _ in
                _ = try await connection.inbound.consume { _ in
                    Issue.record("Invalid compressed data reached the consumer")
                }
            }
        } throws: { error in
            (error as? UpstreamWebSocketFailure)?.kind == .protocolViolation
        }
    }

    @Test("A synthetic request larger than 21 MB round-trips without deleting content", arguments: [false, true])
    func largeSyntheticRequest(compressed: Bool) async throws {
        let messages = WebSocketMessageRecorder()
        let value = String(
            repeating: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/", count: 330_000)
        try await WebSocketCompressionTests().withServer(
            behavior: .init(
                headers: compressed ? ["Sec-WebSocket-Extensions": "permessage-deflate"] : [:],
                echoCompression: compressed),
            configuration: .init(maximumInboundMessageBytes: 32 * 1_024 * 1_024)
        ) { connection, server in
            async let closed = connection.inbound.consume { await messages.append($0) }
            try await connection.outbound.send(.text(value))
            try await connection.outbound.close()
            _ = try await closed
            let identical = await messages.values == [.text(value)]
            #expect(identical)
            let frames = try await server.frames().filter { $0.opcode != .connectionClose }
            let bytes = frames.reduce(0) { $0 + $1.data.readableBytes }
            #expect(compressed ? bytes < value.utf8.count : bytes == value.utf8.count)
            let diagnostics = try #require(await connection.diagnostics())
            #expect(diagnostics.compression == (compressed ? .perMessageDeflate : .none))
            #expect(diagnostics.writtenPayloadBytes == UInt64(bytes))
            #expect(diagnostics.receivedPayloadBytes == UInt64(bytes))
        }
    }

    @Test("Highly compressible outbound input still consumes its full logical message and queue budgets")
    func logicalOutboundLimits() async throws {
        try await WebSocketCompressionTests().withServer(
            behavior: .init(headers: ["Sec-WebSocket-Extensions": "permessage-deflate"], echoCompression: true),
            configuration: .init(
                maximumOutboundMessageBytes: 1_024, outboundFragmentBytes: 512, maximumQueuedBytes: 512)
        ) { connection, server in
            let messages = WebSocketMessageRecorder()
            async let closed = connection.inbound.consume { await messages.append($0) }
            for size in [1_024, 2_048] {
                await #expect {
                    try await connection.outbound.send(.text(String(repeating: "x", count: size)))
                } throws: { error in
                    guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
                    return failure.submission == .notSubmitted
                        && failure.cause.kind == (size == 2_048 ? .messageTooLarge : .outboundQueueFull)
                }
            }
            try await connection.outbound.send(.text("still usable"))
            try await connection.outbound.close()
            _ = try await closed
            #expect(await messages.values == [.text("still usable")])
            #expect(try await server.frames().filter { $0.opcode == .text }.count == 1)
        }
    }
}
