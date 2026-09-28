import Foundation
import NIOCore
import NIOPosix
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketOperationTests {
    @Test func originalOperationErrorWinsOverChannelCleanup() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport()
        do {
            await #expect(throws: OperationStopped.self) {
                try await transport.withConnection(Self.request(port: server.port)) { _ in throw OperationStopped() }
            }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func cancellationWhileReadingIdlePeerJoinsTheReader() async throws {
        let server = try await WebSocketTestServer.start()
        let transport = try NIOUpstreamWebSocketTransport()
        let entered = MultiThreadedEventLoopGroup.singleton.next().makePromise(of: Void.self)
        do {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    do {
                        try await transport.withConnection(Self.request(port: server.port)) { connection in
                            entered.succeed(())
                            _ = try await connection.inbound.consume { _ in }
                        }
                        return false
                    } catch is CancellationError {
                        return true
                    }
                }
                try await entered.futureResult.get()
                group.cancelAll()
                #expect(try await group.next() == true)
            }
            try await transport.shutdown()
            try await server.stop()
        } catch {
            try? await transport.shutdown()
            try? await server.stop()
            throw error
        }
    }

    @Test func messageCallbacksAreSequentialAndApplyBackpressure() async throws {
        let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
        let entered = eventLoop.makePromise(of: Void.self)
        let release = eventLoop.makePromise(of: Void.self)
        let messages = WebSocketMessageRecorder()
        var close = ByteBuffer()
        close.writeInteger(UInt16(1_000))
        let server = try await WebSocketTestServer.start(
            behavior: .init(initialFrames: [
                .init(fin: true, opcode: .text, data: ByteBuffer(string: "first")),
                .init(fin: true, opcode: .text, data: ByteBuffer(string: "second")),
                .init(fin: true, opcode: .connectionClose, data: close),
            ]))
        let transport = try NIOUpstreamWebSocketTransport()
        do {
            try await transport.withConnection(Self.request(port: server.port)) { connection in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        _ = try await connection.inbound.consume { message in
                            await messages.append(message)
                            if message == .text("first") {
                                entered.succeed(())
                                try await release.futureResult.get()
                            }
                        }
                    }
                    try await entered.futureResult.get()
                    #expect(await messages.values == [.text("first")])
                    release.succeed(())
                    try await group.waitForAll()
                }
            }
            #expect(await messages.values == [.text("first"), .text("second")])
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

private struct OperationStopped: Error {}
