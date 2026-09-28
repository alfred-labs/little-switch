import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket

struct WebSocketTestServer: Sendable {
    struct Behavior: Sendable {
        var headers: HTTPHeaders = .init()
        var initialFrames: [WebSocketFrame] = []
        var echo = true
        var acknowledgeClose = true
        var stopReadingAfterUpgrade = false
        var closeOnFirstDataFrame = false
        var keepConnectionOpenAfterClose = false
    }

    private final class State {
        var channels: [any Channel] = []
        var frames: [WebSocketFrame] = []
        var requests: [HTTPRequestHead] = []
    }

    private let listener: any Channel
    private let state: NIOLoopBoundBox<State>
    let port: Int

    static func start(behavior: Behavior = .init(), tlsContext: NIOSSLContext? = nil) async throws -> Self {
        let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
        let state = NIOLoopBoundBox.makeBoxSendingValue(State(), eventLoop: eventLoop)
        let listener = try await ServerBootstrap(group: eventLoop)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    state.value.channels.append(channel)
                    if let tlsContext {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: tlsContext))
                    }
                    let upgrader = NIOWebSocketServerUpgrader(
                        maxFrameSize: 8 * 1_024 * 1_024,
                        shouldUpgrade: { channel, request in
                            state.value.requests.append(request)
                            return channel.eventLoop.makeSucceededFuture(behavior.headers)
                        },
                        upgradePipelineHandler: { channel, _ in
                            channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(
                                    EchoHandler(behavior: behavior) { frame in
                                        state.value.frames.append(frame)
                                    })
                                for frame in behavior.initialFrames { channel.write(frame, promise: nil) }
                                channel.flush()
                                if behavior.stopReadingAfterUpgrade {
                                    try channel.syncOptions?.setOption(ChannelOptions.autoRead, value: false)
                                }
                            }
                        })
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(
                        withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in }))
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        guard let port = listener.localAddress?.port else {
            try await listener.close()
            throw WebSocketServerFailure.missingPort
        }
        return Self(listener: listener, state: state, port: port)
    }

    func frames() async throws -> [WebSocketFrame] {
        try await state.eventLoop.submit { state.value.frames }.get()
    }

    func requests() async throws -> [HTTPRequestHead] {
        try await state.eventLoop.submit { state.value.requests }.get()
    }

    func send(_ frame: WebSocketFrame) async throws {
        let sending = state.eventLoop.flatSubmit {
            EventLoopFuture.andAllSucceed(
                state.value.channels.map { $0.writeAndFlush(frame) }, on: state.eventLoop)
        }
        try await sending.get()
    }

    func waitForConnectionsToClose() async throws {
        let closed = state.eventLoop.flatSubmit {
            EventLoopFuture.andAllSucceed(state.value.channels.map(\.closeFuture), on: state.eventLoop)
        }
        try await closed.get()
    }

    func stop() async throws {
        try await listener.close()
        let closed = state.eventLoop.flatSubmit {
            let connections = state.value.channels
            state.value.channels.removeAll()
            return EventLoopFuture.andAllSucceed(
                connections.map { channel in
                    let closed: EventLoopFuture<Void>
                    if let tls = try? channel.pipeline.syncOperations.context(handlerType: NIOSSLServerHandler.self) {
                        closed = tls.close()
                    } else {
                        closed = channel.close()
                    }
                    return closed.flatMapError { _ in state.eventLoop.makeSucceededVoidFuture() }
                },
                on: state.eventLoop)
        }
        try await closed.get()
    }
}

private final class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private let behavior: WebSocketTestServer.Behavior
    private let received: (WebSocketFrame) -> Void
    private var sentClose: Bool

    init(behavior: WebSocketTestServer.Behavior, received: @escaping (WebSocketFrame) -> Void) {
        self.behavior = behavior
        self.received = received
        self.sentClose = behavior.initialFrames.contains { $0.opcode == .connectionClose }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        received(frame)
        switch frame.opcode {
        case .connectionClose:
            guard behavior.acknowledgeClose, !behavior.keepConnectionOpenAfterClose else { return }
            let channel = context.channel
            if sentClose {
                channel.close(promise: nil)
            } else {
                let written = context.eventLoop.makePromise(of: Void.self)
                context.writeAndFlush(
                    wrapOutboundOut(
                        .init(
                            fin: true, opcode: .connectionClose, data: frame.unmaskedData)), promise: written)
                written.futureResult.whenComplete { _ in channel.close(promise: nil) }
            }
        case .ping:
            context.writeAndFlush(
                wrapOutboundOut(.init(fin: true, opcode: .pong, data: frame.unmaskedData)), promise: nil)
        case .text, .binary, .continuation:
            if behavior.closeOnFirstDataFrame, !sentClose {
                sentClose = true
                var close = ByteBuffer()
                close.writeInteger(UInt16(1_000))
                context.writeAndFlush(
                    wrapOutboundOut(.init(fin: true, opcode: .connectionClose, data: close)), promise: nil)
            }
            if behavior.echo {
                context.writeAndFlush(
                    wrapOutboundOut(
                        .init(
                            fin: frame.fin, opcode: frame.opcode, data: frame.unmaskedData)), promise: nil)
            }
        default:
            break
        }
    }
}

private enum WebSocketServerFailure: Error {
    case missingPort
}
