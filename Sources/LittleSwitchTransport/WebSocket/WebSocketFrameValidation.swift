import Foundation
import NIOCore
import NIOSSL
import NIOWebSocket

enum WebSocketCloseValidation {
    static func valid(code: UInt16) -> Bool {
        (1_000...1_003).contains(code) || (1_007...1_014).contains(code) || (3_000...4_999).contains(code)
    }

    static func decode(_ data: ByteBuffer) throws -> UpstreamWebSocketPeerClose {
        guard data.readableBytes != 1 else { throw UpstreamWebSocketFailure(kind: .protocolViolation) }
        guard data.readableBytes > 0 else { return .init(code: nil, reason: nil) }
        guard let code = data.getInteger(at: data.readerIndex, as: UInt16.self), valid(code: code) else {
            throw UpstreamWebSocketFailure(kind: .protocolViolation)
        }
        let bytes = data.readableBytesView.dropFirst(2)
        guard let reason = String(bytes: bytes, encoding: .utf8) else {
            throw UpstreamWebSocketFailure(kind: .protocolViolation)
        }
        return .init(code: code, reason: bytes.isEmpty ? nil : reason)
    }
}

final class WebSocketFrameValidation: ChannelDuplexHandler {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = WebSocketFrame
    typealias OutboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private let control: WebSocketConnectionControl

    init(control: WebSocketConnectionControl) { self.control = control }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var frame = unwrapInboundIn(data)
        do {
            guard frame.maskKey == nil, !frame.rsv1, !frame.rsv2, !frame.rsv3 else {
                throw UpstreamWebSocketFailure(kind: .protocolViolation)
            }
            switch frame.opcode {
            case .text, .binary, .continuation:
                break
            case .ping, .pong:
                guard frame.fin, frame.data.readableBytes <= 125 else {
                    throw UpstreamWebSocketFailure(kind: .protocolViolation)
                }
            case .connectionClose:
                guard frame.fin, frame.data.readableBytes <= 125 else {
                    throw UpstreamWebSocketFailure(kind: .protocolViolation)
                }
                let close = try WebSocketCloseValidation.decode(frame.data)
                control.state.value.receivedClose(close, control: control)
                // WSCore 1.6.1 predates these registered codes. Keep exact peer
                // metadata and let its private state machine perform a normal acknowledgement.
                if let code = close.code, (1_012...1_014).contains(code) {
                    frame.data.setInteger(UInt16(1_001), at: frame.data.readerIndex)
                }
            default:
                throw UpstreamWebSocketFailure(kind: .protocolViolation)
            }
            context.fireChannelRead(wrapInboundOut(frame))
        } catch {
            control.state.value.abort(error)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        control.state.value.physicalConnectionClosed()
        if control.state.value.peerClose == nil {
            control.state.value.abort(UpstreamWebSocketFailure(kind: .connectionLost))
        }
        context.fireChannelInactive()
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let frame = unwrapOutboundIn(data)
        switch frame.opcode {
        case .text, .binary, .continuation:
            // The decision and forwarding share the event loop with receivedClose.
            // This also catches a fragment already yielded by the asynchronous pump.
            guard control.state.value.permitsDataFrames else {
                promise?.fail(UpstreamWebSocketFailure(kind: .connectionClosing))
                return
            }
            let identifier = control.state.value.dataWriteIdentifier
            let written = context.eventLoop.makePromise(of: Void.self)
            let control = control
            written.futureResult.whenComplete {
                control.state.value.completedDataWrite(identifier, result: $0)
            }
            if let promise { written.futureResult.cascade(to: promise) }
            context.write(wrapOutboundOut(frame), promise: written)
            return
        case .connectionClose:
            control.state.value.sentClose()
            // NIOAsyncChannel yields without awaiting socket writes. Join this
            // write before a completed consumer can let WSCore close its scope.
            let written = context.eventLoop.makePromise(of: Void.self)
            let control = control
            written.futureResult.whenComplete { control.state.value.completedCloseWrite($0) }
            if let promise { written.futureResult.cascade(to: promise) }
            context.write(wrapOutboundOut(frame), promise: written)
            return
        default:
            break
        }
        context.write(wrapOutboundOut(frame), promise: promise)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        // NIOTS emits ioOnClosedChannel for a local close. Neither that event nor
        // a missing TLS close_notify invalidates an already validated WS close.
        let expectedClose = error as? NIOSSLError == .uncleanShutdown || error as? ChannelError == .ioOnClosedChannel
        if control.state.value.peerClose != nil, expectedClose {
            return
        }
        let kind: UpstreamWebSocketFailure.Kind =
            if let frameError = error as? NIOWebSocketError {
                frameError == .invalidFrameLength ? .messageTooLarge : .protocolViolation
            } else {
                .connectionLost
            }
        control.state.value.abort(UpstreamWebSocketFailure(kind: kind))
    }
}
