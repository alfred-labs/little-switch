import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

struct WebSocketHTTPTestServer: Sendable {
    struct Reply: Sendable {
        var status: HTTPResponseStatus = .tooManyRequests
        var headers: HTTPHeaders = .init()
        var body: Data = .init()
        var finish = true
        var closeAfterBody = false
        var sendHead = true
    }

    private final class State {
        var channels: [any Channel] = []
        let request: EventLoopPromise<HTTPRequestHead>
        var receivedRequest = false

        init(eventLoop: any EventLoop) {
            request = eventLoop.makePromise()
        }
    }

    private let listener: any Channel
    private let state: NIOLoopBoundBox<State>
    let port: Int

    static func start(reply: Reply) async throws -> Self {
        let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
        let state = NIOLoopBoundBox.makeBoxSendingValue(State(eventLoop: eventLoop), eventLoop: eventLoop)
        let listener = try await ServerBootstrap(group: eventLoop)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    state.value.channels.append(channel)
                    // A deliberately silent response must still read the peer's FIN.
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(withPipeliningAssistance: false)
                    try channel.pipeline.syncOperations.addHandler(
                        ReplyHandler(reply: reply) { head in
                            if !state.value.receivedRequest {
                                state.value.receivedRequest = true
                                state.value.request.succeed(head)
                            }
                        })
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        guard let port = listener.localAddress?.port else {
            try await listener.close()
            throw TestServerError.missingPort
        }
        return Self(listener: listener, state: state, port: port)
    }

    func request() async throws -> HTTPRequestHead {
        try await state.eventLoop.flatSubmit { state.value.request.futureResult }.get()
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
            if !state.value.receivedRequest {
                state.value.receivedRequest = true
                state.value.request.fail(TestServerError.stopped)
            }
            return EventLoopFuture.andAllSucceed(
                connections.map { $0.close().flatMapError { _ in state.eventLoop.makeSucceededVoidFuture() } },
                on: state.eventLoop)
        }
        try await closed.get()
    }
}

private final class ReplyHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let reply: WebSocketHTTPTestServer.Reply
    private let received: (HTTPRequestHead) -> Void

    init(reply: WebSocketHTTPTestServer.Reply, received: @escaping (HTTPRequestHead) -> Void) {
        self.reply = reply
        self.received = received
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            received(head)
        case .end:
            guard reply.sendHead else { return }
            var headers = reply.headers
            if !headers.contains(name: "Content-Length") {
                headers.add(name: "Content-Length", value: String(reply.body.count))
            }
            let head = HTTPResponseHead(version: .http1_1, status: reply.status, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: reply.body)))), promise: nil)
            if reply.finish { context.write(wrapOutboundOut(.end(nil)), promise: nil) }
            context.flush()
            if reply.closeAfterBody { context.close(promise: nil) }
        case .body:
            break
        }
    }
}

private enum TestServerError: Error {
    case missingPort
    case stopped
}
