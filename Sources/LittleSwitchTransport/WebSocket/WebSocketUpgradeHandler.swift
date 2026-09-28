import NIOCore
import NIOHTTP1
import NIOWebSocket

enum WebSocketUpgradeHandler {
    static func configure(
        channel: any Channel,
        request: HTTPRequestHead,
        control: WebSocketConnectionControl,
        configuration: UpstreamWebSocketConfiguration
    ) throws {
        let encoder = HTTPRequestEncoder()
        var limits = NIOHTTPDecoderLimitConfiguration()
        limits.maxHeaderFieldSize = configuration.maximumHeaderFieldBytes
        limits.maxHeaderListSize = configuration.maximumHeaderBytes
        limits.maxHeaderFieldCount = configuration.maximumHeaderCount
        let decoder = ByteToMessageHandler(
            HTTPResponseDecoder(
                leftOverBytesStrategy: .forwardBytes, limitConfiguration: limits))
        let validator = NIOHTTPRequestHeadersValidator()
        let observer = WebSocketUpgradeHeadObserver(control: control)
        let websocket = NIOTypedWebSocketClientUpgrader<WebSocketUpgradeOutcome>(
            maxFrameSize: configuration.maximumInboundMessageBytes,
            // Our frame handler owns protocol failure and close transitions. An
            // earlier automatic error handler could write a close around its gate.
            enableAutomaticErrorHandling: false
        ) { channel, head in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(WebSocketFrameValidation(control: control))
                let framed = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(
                    wrappingChannelSynchronously: channel,
                    configuration: .init(backPressureStrategy: .init(lowWatermark: 1, highWatermark: 2)))
                return .upgraded(framed, head)
            }
        }
        let upgradeConfiguration = NIOTypedHTTPClientUpgradeConfiguration(
            upgradeRequestHead: request,
            upgraders: [ValidatedWebSocketUpgrader(base: websocket)]
        ) { channel in
            channel.eventLoop.makeCompletedFuture {
                let response = control.state.value.startRejection(control: control)
                try channel.pipeline.syncOperations.addHandler(WebSocketRejectionCollector(control: control))
                return .rejected(response)
            }
        }
        let upgrade = NIOTypedHTTPClientUpgradeHandler(
            httpHandlers: [encoder, decoder, validator, observer],
            upgradeConfiguration: upgradeConfiguration)
        try channel.pipeline.syncOperations.addHandlers(encoder, decoder, validator, observer, upgrade)
        upgrade.upgradeResultFuture.whenComplete { control.state.value.completeHandshake($0) }
    }
}

private struct ValidatedWebSocketUpgrader: NIOTypedHTTPClientProtocolUpgrader {
    let base: NIOTypedWebSocketClientUpgrader<WebSocketUpgradeOutcome>
    let supportedProtocol = "websocket"
    let requiredUpgradeHeaders: [String] = []

    func addCustom(upgradeRequestHeaders: inout HTTPHeaders) {
        base.addCustom(upgradeRequestHeaders: &upgradeRequestHeaders)
    }

    func shouldAllowUpgrade(upgradeResponse: HTTPResponseHead) -> Bool {
        upgradeResponse.version == .http1_1
            && upgradeResponse.headers[canonicalForm: "Connection"].contains { $0.lowercased() == "upgrade" }
            && upgradeResponse.headers[canonicalForm: "Upgrade"].contains { $0.lowercased() == "websocket" }
            && !upgradeResponse.headers.contains(name: "Sec-WebSocket-Extensions")
            && !upgradeResponse.headers.contains(name: "Sec-WebSocket-Protocol")
            && base.shouldAllowUpgrade(upgradeResponse: upgradeResponse)
    }

    func upgrade(channel: any Channel, upgradeResponse: HTTPResponseHead) -> EventLoopFuture<WebSocketUpgradeOutcome> {
        base.upgrade(channel: channel, upgradeResponse: upgradeResponse)
    }
}

private final class WebSocketUpgradeHeadObserver: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias InboundOut = HTTPClientResponsePart
    let control: WebSocketConnectionControl

    init(control: WebSocketConnectionControl) { self.control = control }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head(let head) = unwrapInboundIn(data) { control.state.value.observe(head) }
        context.fireChannelRead(data)
    }
}

private final class WebSocketRejectionCollector: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    let control: WebSocketConnectionControl

    init(control: WebSocketConnectionControl) { self.control = control }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head: break
        case .body(let buffer): control.state.value.appendRejection(buffer)
        case .end: control.state.value.finishRejection(.complete)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        control.state.value.finishRejection(.connectionClosed)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        control.state.value.finishRejection(.invalidHTTP)
    }
}
