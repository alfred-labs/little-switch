import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

struct WebSocketConnectionTests {
    @Test func readsMessagesAndPreservesUpgradeHeaders() async throws {
        var close = ByteBuffer()
        close.writeInteger(UInt16(1_000))
        let server = try await WebSocketTestServer.start(
            behavior: .init(
                headers: ["X-Turn-State": "ready"],
                initialFrames: [
                    .init(fin: true, opcode: .text, data: ByteBuffer(string: "welcome")),
                    .init(fin: true, opcode: .connectionClose, data: close),
                ]))
        let transport = try NIOUpstreamWebSocketTransport()
        let messages = WebSocketMessageRecorder()
        do {
            try await transport.withConnection(request(port: server.port)) { connection in
                #expect(connection.handshake.headers["X-Turn-State"] == ["ready"])
                let closed = try await connection.inbound.consume { await messages.append($0) }
                #expect(closed == .init(code: 1_000, reason: nil))
                await #expect(throws: UpstreamWebSocketFailure.self) {
                    try await connection.inbound.consume { _ in }
                }
            }
            #expect(await messages.values == [.text("welcome")])
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func concurrentSendsKeepWholeMessagesAndClientMasking() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(outboundFragmentBytes: 3))
        let messages = WebSocketMessageRecorder()
        let values = ["abcdefgh", "12345678", "ABCDEFGH", "87654321"]
        do {
            try await transport.withConnection(request(port: server.port)) { connection in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        _ = try await connection.inbound.consume { await messages.append($0) }
                    }
                    try await withThrowingTaskGroup(of: Void.self) { sends in
                        for value in values {
                            sends.addTask { try await connection.outbound.send(.text(value)) }
                        }
                        try await sends.waitForAll()
                    }
                    try await connection.outbound.close()
                    try await group.waitForAll()
                }
            }
            let received = await messages.values.compactMap { message -> String? in
                guard case .text(let value) = message else { return nil }
                return value
            }
            #expect(received.sorted() == values.sorted())
            let frames = try await server.frames()
            #expect(frames.allSatisfy { $0.maskKey != nil })
            #expect(frames.filter { $0.opcode == .text }.count == 4)
            #expect(frames.filter { $0.opcode == .continuation }.count == 8)
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func preservesEmptyMessagesAndUTF8AcrossOutboundFragments() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(outboundFragmentBytes: 3))
        let messages = WebSocketMessageRecorder()
        let values: [UpstreamWebSocketMessage] = [
            .text(""), .binary(Data()), .text("🍐é漢"), .binary(Data([0, 255, 1, 254])),
        ]
        do {
            try await transport.withConnection(request(port: server.port)) { connection in
                async let closed = connection.inbound.consume { await messages.append($0) }
                for value in values { try await connection.outbound.send(value) }
                try await connection.outbound.close()
                _ = try await closed
            }
            #expect(await messages.values == values)
            let frames = try await server.frames().filter { $0.opcode != .connectionClose }
            #expect(frames.prefix(2).allSatisfy { $0.fin && $0.unmaskedData.readableBytes == 0 })
            #expect(frames.allSatisfy { $0.unmaskedData.readableBytes <= 3 && $0.maskKey != nil })
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    private func request(port: Int) throws -> UpstreamWebSocketRequest {
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/responses"))
        return try UpstreamWebSocketRequest(url: url)
    }
}

actor WebSocketMessageRecorder {
    private(set) var values: [UpstreamWebSocketMessage] = []
    func append(_ value: UpstreamWebSocketMessage) { values.append(value) }
}
