import NIOCore
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketCloseWriteTests {
    @Test(arguments: [false, true])
    func closeWaitsForLocalWritingIndependentlyOfThePeerReply(peerRepliesFirst: Bool) async throws {
        let fixture = try await WebSocketDataWriteFixture.start(holdClose: true, acknowledgeClose: false)
        let completion = WebSocketSendCompletion()
        do {
            try await fixture.run { connection in
                async let peer = connection.inbound.consume { _ in }
                let close = Task {
                    try await connection.outbound.close()
                    await completion.finish()
                }
                try await fixture.received.get()
                var reply = ByteBuffer()
                reply.writeInteger(UInt16(1_000))
                if peerRepliesFirst {
                    try await fixture.server.send(.init(fin: true, opcode: .connectionClose, data: reply))
                }
                try await Task.sleep(for: .milliseconds(30))
                #expect(await completion.finished == false)
                try await fixture.release()
                try await close.value
                #expect(await completion.finished)
                if !peerRepliesFirst {
                    try await fixture.server.send(.init(fin: true, opcode: .connectionClose, data: reply))
                }
                let received = try await peer
                #expect(received == .init(code: 1_000, reason: nil))
            }
            try await fixture.stop()
        } catch {
            try? await fixture.stop()
            throw error
        }
    }

    @Test func failedCloseWriteReachesTheCloseCaller() async throws {
        let fixture = try await WebSocketDataWriteFixture.start(holdClose: true)
        do {
            await #expect {
                try await fixture.run { connection in
                    let close = Task { await Self.expectCloseFailure(connection.outbound) }
                    try await fixture.received.get()
                    try await fixture.release(failing: true)
                    await close.value
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

    private static func expectCloseFailure(_ outbound: any UpstreamWebSocketOutbound) async {
        await #expect {
            try await outbound.close()
        } throws: { error in
            guard let failure = error as? UpstreamWebSocketSendFailure else { return false }
            return failure.cause.kind == .writeFailed && failure.submission == .mayHaveBeenSubmitted
        }
    }
}
