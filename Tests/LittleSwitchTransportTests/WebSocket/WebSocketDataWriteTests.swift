import NIOCore
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketDataWriteTests {
    @Test(arguments: [false, true])
    func sendKeepsItsQueueBudgetUntilTheLastFragmentIsWritten(compressed: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(fragment: 2, compressed: compressed)
        let completion = WebSocketSendCompletion()
        do {
            try await fixture.run { connection in
                let send = Task {
                    try await connection.outbound.send(.text("12345678"))
                    await completion.finish()
                }
                try await fixture.received.get()
                try await Task.sleep(for: .milliseconds(30))
                #expect(await completion.finished == false)
                await #expect {
                    try await connection.outbound.send(.text("x"))
                } throws: { error in
                    guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
                    return failure.cause.kind == .outboundQueueFull && failure.submission == .notSubmitted
                }
                try await fixture.release()
                try await send.value
                #expect(await completion.finished)
                try await connection.outbound.send(.text("next"))
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test(arguments: [1, 2], [false, true])
    func failedFragmentIsReportedAsPossiblySubmitted(fragment: Int, compressed: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(fragment: fragment, compressed: compressed)
        do {
            await #expect {
                try await fixture.run { connection in
                    let send = Task {
                        await Self.expectSendFailure(connection.outbound, kind: .writeFailed)
                    }
                    try await fixture.received.get()
                    try await fixture.release(failing: true)
                    await send.value
                }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .writeFailed
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test(arguments: [false, true])
    func cancellingAHeldDataWriteReleasesThePump(compressed: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(compressed: compressed)
        do {
            await #expect {
                try await fixture.run { connection in
                    let send = Task { await Self.expectSendFailure(connection.outbound, kind: .cancelled) }
                    try await fixture.received.get()
                    send.cancel()
                    await send.value
                }
            } throws: { error in
                (error as? UpstreamWebSocketFailure)?.kind == .cancelled
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test(arguments: [false, true])
    func peerCloseReleasesAHeldDataWriteWithoutLosingItsCloseMetadata(compressed: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(compressed: compressed)
        do {
            try await fixture.run { connection in
                async let peer = connection.inbound.consume { _ in }
                let send = Task { await Self.expectSendFailure(connection.outbound, kind: .connectionClosing) }
                try await fixture.received.get()
                var close = ByteBuffer()
                close.writeInteger(UInt16(1_000))
                try await fixture.server.send(.init(fin: true, opcode: .connectionClose, data: close))
                #expect(try await peer == .init(code: 1_000))
                await send.value
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test(arguments: [false, true])
    func aWrittenPongCannotAcknowledgeAHeldDataFragment(compressed: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(compressed: compressed)
        let completion = WebSocketSendCompletion()
        do {
            try await fixture.run { connection in
                async let peer = connection.inbound.consume { _ in }
                let send = Task {
                    try await connection.outbound.send(.text("12345678"))
                    await completion.finish()
                }
                try await fixture.received.get()
                try await fixture.server.send(.init(fin: true, opcode: .ping, data: ByteBuffer(string: "ping")))
                try await fixture.pongWritten.get()
                #expect(await completion.finished == false)
                try await fixture.release()
                try await send.value
                try await connection.outbound.close()
                #expect(try await peer == .init(code: 1_000))
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    private static func expectSendFailure(
        _ outbound: any UpstreamWebSocketOutbound, kind: UpstreamWebSocketFailure.Kind
    ) async {
        await #expect {
            try await outbound.send(.text("12345678"))
        } throws: { error in
            guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
            return failure.cause.kind == kind && failure.submission == .mayHaveBeenSubmitted
        }
    }
}
