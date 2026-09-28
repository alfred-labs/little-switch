import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import NIOTransportServices
import NIOWebSocket
import Testing

@testable import LittleSwitchTransport

struct WebSocketDataWriteFixture: Sendable {
    let control: WebSocketConnectionControl
    let server: WebSocketTestServer
    let channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>
    let handshake: HTTPResponseHead
    let configuration: UpstreamWebSocketConfiguration
    let held: NIOLoopBoundBox<HeldWebSocketDataWrite>
    let received: EventLoopFuture<Void>
    let pongWritten: EventLoopFuture<Void>

    static func start(
        fragment: Int = 1, fragmentBytes: Int = 4, holdClose: Bool = false, acknowledgeClose: Bool = true
    ) async throws -> Self {
        let server = try await WebSocketTestServer.start(
            behavior: .init(echo: false, acknowledgeClose: acknowledgeClose))
        let configuration = UpstreamWebSocketConfiguration(
            closeTimeout: .seconds(1),
            outboundFragmentBytes: fragmentBytes,
            maximumQueuedMessages: 1,
            maximumQueuedBytes: 8)
        let control = WebSocketConnectionControl(
            eventLoop: NIOTSEventLoopGroup.singleton.next(), configuration: configuration)
        let received = control.eventLoop.makePromise(of: Void.self)
        let pongWritten = control.eventLoop.makePromise(of: Void.self)
        let held = NIOLoopBoundBox.makeBoxSendingValue(
            HeldWebSocketDataWrite(
                fragment: fragment, holdClose: holdClose, received: received, pongWritten: pongWritten),
            eventLoop: control.eventLoop)
        do {
            let request = try UpstreamWebSocketRequest(
                url: #require(URL(string: "ws://127.0.0.1:\(server.port)/responses")))
            let outcome = try await WebSocketClientBootstrap.connect(
                request: request,
                configuration: configuration,
                tlsContext: NIOSSLContext(configuration: .makeClientConfiguration()),
                control: control)
            // swiftlint:disable:next pattern_matching_keywords
            guard case .upgraded(let channel, let handshake) = outcome else {
                throw UpstreamWebSocketFailure(kind: .invalidUpgrade)
            }
            let installed = control.eventLoop.submit {
                let validator = try channel.channel.pipeline.syncOperations.handler(type: WebSocketFrameValidation.self)
                try channel.channel.pipeline.syncOperations.addHandler(held.value, position: .before(validator))
            }
            try await installed.get()
            return .init(
                control: control,
                server: server,
                channel: channel,
                handshake: handshake,
                configuration: configuration,
                held: held,
                received: received.futureResult,
                pongWritten: pongWritten.futureResult)
        } catch {
            control.abort(error)
            await control.close()
            try? await server.stop()
            throw error
        }
    }

    func run(_ operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void) async throws {
        do {
            try await WSCoreConnectionDriver.run(
                channel: channel,
                handshake: handshake,
                control: control,
                configuration: configuration,
                operation: operation)
        } catch {
            throw await control.normalized(error)
        }
    }

    func release(failing: Bool = false) async throws {
        try await control.eventLoop.submit { held.value.release(failing: failing) }.get()
    }

    func stop() async throws {
        try await release(failing: true)
        control.abort(UpstreamWebSocketFailure(kind: .connectionEnded))
        await control.close()
        try await server.stop()
    }
}

final class HeldWebSocketDataWrite: ChannelOutboundHandler {
    typealias OutboundIn = WebSocketFrame
    private struct Pending {
        let context: ChannelHandlerContext
        let data: NIOAny
        let promise: EventLoopPromise<Void>?
    }
    private let fragment: Int
    private let holdClose: Bool
    private let received: EventLoopPromise<Void>
    private let pongWritten: EventLoopPromise<Void>
    private var observedPong = false
    private var count = 0
    private var held: Pending?

    init(fragment: Int, holdClose: Bool, received: EventLoopPromise<Void>, pongWritten: EventLoopPromise<Void>) {
        self.fragment = fragment
        self.holdClose = holdClose
        self.received = received
        self.pongWritten = pongWritten
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let opcode = unwrapOutboundIn(data).opcode
        switch opcode {
        case .text, .binary, .continuation:
            if !holdClose, hold(context: context, data: data, promise: promise) { return }
        case .connectionClose:
            if holdClose, hold(context: context, data: data, promise: promise) { return }
        case .pong where !observedPong:
            observedPong = true
            if let promise { pongWritten.futureResult.cascade(to: promise) }
            context.write(data, promise: pongWritten)
            return
        default: break
        }
        context.write(data, promise: promise)
    }

    private func hold(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) -> Bool {
        count += 1
        guard count == fragment else { return false }
        held = .init(context: context, data: data, promise: promise)
        received.succeed(())
        return true
    }

    func release(failing: Bool) {
        guard let pending = held else { return }
        held = nil
        if failing {
            // Model a socket write completion failure without errorCaught.
            pending.promise?.fail(HeldWriteFailure.refused)
        } else {
            pending.context.writeAndFlush(pending.data, promise: pending.promise)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        if !observedPong { pongWritten.succeed(()) }
        release(failing: true)
    }
}

private enum HeldWriteFailure: Error { case refused }

actor WebSocketSendCompletion {
    private(set) var finished = false
    func finish() { finished = true }
}
