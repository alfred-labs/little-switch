import NIOCore
import NIOPosix
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

@Suite(.timeLimit(.minutes(1)))
struct WebSocketCloseWriteFailureTests {
    @Test(arguments: [false, true])
    func aFailedAcknowledgementRequiresAnAlreadyObservedPhysicalClose(physicalCloseFirst: Bool) async throws {
        let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
        let control = WebSocketConnectionControl(eventLoop: eventLoop, configuration: .init())
        let injected = eventLoop.makePromise(of: Void.self)
        let channel = try await ServerBootstrap(group: eventLoop)
            .serverChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try control.state.value.register(channel)
                    try channel.pipeline.syncOperations.addHandlers(
                        FailedCloseWriteHandler(physicalCloseFirst: physicalCloseFirst, injected: injected),
                        WebSocketFrameValidation(control: control))
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        do {
            let received = eventLoop.flatSubmit {
                control.state.value.receivedClose(.init(code: 1_000, reason: nil), control: control)
                let closed = control.state.value.waitForCloseWrite().flatMapThrowing {
                    try control.state.value.receivedPeerClose()
                }
                var payload = ByteBuffer()
                payload.writeInteger(UInt16(1_000))
                channel.writeAndFlush(
                    WebSocketFrame(fin: true, opcode: .connectionClose, data: payload), promise: nil)
                return closed
            }
            try await injected.futureResult.get()
            if physicalCloseFirst {
                #expect(try await received.get() == .init(code: 1_000, reason: nil))
            } else {
                await #expect {
                    try await received.get()
                } throws: { error in
                    (error as? UpstreamWebSocketFailure)?.kind == .writeFailed
                }
            }
            control.abort(UpstreamWebSocketFailure(kind: .connectionEnded))
            await control.close()
        } catch {
            control.abort(error)
            await control.close()
            throw error
        }
    }
}

private final class FailedCloseWriteHandler: ChannelOutboundHandler {
    typealias OutboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private let physicalCloseFirst: Bool
    private let injected: EventLoopPromise<Void>

    init(physicalCloseFirst: Bool, injected: EventLoopPromise<Void>) {
        self.physicalCloseFirst = physicalCloseFirst
        self.injected = injected
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard unwrapOutboundIn(data).opcode == .connectionClose else {
            context.write(data, promise: promise)
            return
        }
        if physicalCloseFirst {
            let injected = injected
            context.channel.closeFuture.whenComplete { _ in
                promise?.fail(FailedCloseWrite.refused)
                injected.succeed(())
            }
            context.close(promise: nil)
        } else {
            // Model NIOTS contentProcessed: only the write promise fails.
            // Do not synthesize errorCaught or channelInactive here.
            promise?.fail(FailedCloseWrite.refused)
            injected.succeed(())
        }
    }
}

private enum FailedCloseWrite: Error {
    case refused
}
