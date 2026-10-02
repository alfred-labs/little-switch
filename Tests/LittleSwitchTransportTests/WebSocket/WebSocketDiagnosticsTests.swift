import Foundation
import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite("WebSocket wire diagnostics", .timeLimit(.minutes(1)))
struct WebSocketDiagnosticsTests {
    @Test("A socket error keeps its original numeric code before normalization")
    func socketFailureCause() async throws {
        let fixture = try await WebSocketDataWriteFixture.start()
        do {
            await #expect {
                try await fixture.run { connection in
                    async let peer = connection.inbound.consume { _ in }
                    let send = Task { try? await connection.outbound.send(.text("12345678")) }
                    try await fixture.received.get()
                    let failed = fixture.control.eventLoop.submit {
                        fixture.channel.channel.pipeline.fireErrorCaught(
                            IOError(errnoCode: 54, reason: "private-wire-secret"))
                    }
                    try await failed.get()
                    _ = await send.value
                    _ = try await peer
                }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .connectionLost
            }
            let snapshot = try await fixture.control.eventLoop.submit { fixture.control.state.value.diagnostics }.get()
            #expect((snapshot.underlyingError as? IOError)?.errnoCode == 54)
            #expect(snapshot.closeOrigin == nil)
            #expect(snapshot.peerCloseCode == nil)
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test(
        "A peer close during a fragmented send retains its code and excludes unwritten bytes",
        arguments: [UInt16(1_009), 1_013], [false, true])
    func fragmentedPeerClose(code: UInt16, compressed: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(fragment: 2, compressed: compressed)
        do {
            try await fixture.run { connection in
                async let peer = connection.inbound.consume { _ in }
                let send = Task {
                    await #expect {
                        try await connection.outbound.send(.text("12345678"))
                    } throws: { error in
                        (error as? UpstreamWebSocketSendFailure)?.submission == .mayHaveBeenSubmitted
                            && (error as? UpstreamWebSocketSendFailure)?.cause.peerCloseCode == code
                    }
                }
                try await fixture.received.get()
                var close = ByteBuffer()
                close.writeInteger(code)
                close.writeString("private-close-reason")
                try await fixture.server.send(.init(fin: true, opcode: .connectionClose, data: close))
                #expect(try await peer.code == code)
                _ = await send.value
                let snapshot = try #require(await connection.diagnostics())
                let frame = try #require(try await fixture.server.frames().first { $0.opcode == .text })
                #expect(frame.rsv1 == compressed)
                #expect(snapshot.writtenPayloadBytes == UInt64(frame.data.readableBytes))
                #expect(snapshot.compression == (compressed ? .perMessageDeflate : .none))
                #expect(snapshot.writtenDataFrames == 1)
                #expect(snapshot.receivedPayloadBytes == 0)
                #expect(snapshot.closeOrigin == .peer)
                #expect(snapshot.peerCloseCode == code)
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test("A locally initiated close is not confused with its peer acknowledgement")
    func localClose() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport(configuration: .init(outboundFragmentBytes: 2))
        do {
            let request = try UpstreamWebSocketRequest(
                url: #require(URL(string: "ws://127.0.0.1:\(server.port)/responses")))
            try await transport.withConnection(request) { connection in
                async let peer = connection.inbound.consume { _ in }
                try await connection.outbound.send(.text("hello"))
                try await connection.outbound.close(code: 1_000, reason: nil)
                #expect(try await peer.code == 1_000)
                let snapshot = try #require(await connection.diagnostics())
                #expect(snapshot.writtenPayloadBytes == 5)
                #expect(snapshot.writtenDataFrames == 3)
                #expect(snapshot.receivedPayloadBytes == 5)
                #expect(snapshot.receivedDataFrames == 3)
                #expect(snapshot.closeOrigin == .local)
                #expect(snapshot.peerCloseCode == 1_000)
                #expect(snapshot.localCloseCode == 1_000)
            }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }
}
