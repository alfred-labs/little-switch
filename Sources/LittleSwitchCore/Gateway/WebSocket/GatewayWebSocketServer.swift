import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdCore
import HummingbirdWebSocket
import LittleSwitchTransport
import Logging
import NIOCore
import NIOSSL
import NIOWebSocket

/// The HTTP responder remains the authority for every non-upgraded request.
/// Hummingbird owns WebSocket framing, control messages and close handshakes.
package enum GatewayWebSocketServer {
    package static func make(
        responder: GatewayResponder,
        requiredAuthorityPort: Int?,
        tlsConfiguration: TLSConfiguration? = nil,
        limits: ResponsesWebSocketLimits = .init(),
        upstreamTransport: (any UpstreamWebSocketTransport)? = nil
    ) throws -> HTTPServerBuilder {
        let policy = GatewayWebSocketHandshakePolicy(requiredAuthorityPort: requiredAuthorityPort)
        let makeChild = { @Sendable (httpResponder: @escaping HTTPChannelHandler.Responder) in
            let channel = HTTP1WebSocketUpgradeChannel(
                responder: httpResponder,
                configuration: .init(
                    ws: .init(
                        maxFrameSize: limits.maxFrameBytes,
                        extensions: [],
                        autoPing: .enabled(timePeriod: .seconds(30)),
                        closeTimeout: .seconds(limits.closeGraceSeconds),
                        validateUTF8: true
                    )
                )
            ) { head, networkChannel, _ in
                guard policy.allows(head) else {
                    // A refused upgrade is HTTP 400 in Hummingbird. It never
                    // reaches a Responses session or upstream admission.
                    return .dontUpgrade
                }
                let request = Request(head: head, body: .init(buffer: ByteBuffer()))
                return .upgrade([:]) { inbound, outbound, _ in
                    GatewayWebSocketDeadline.install(
                        on: networkChannel,
                        lifetime: .seconds(limits.connectionLifetimeSeconds),
                        closeGrace: .seconds(limits.closeGraceSeconds)
                    )
                    let messages = inbound.messages(maxSize: limits.maxFrameBytes).map { message in
                        try await receiveMessage(message, maximumBytes: limits.maxFrameBytes) { code, reason in
                            try await outbound.close(code, reason: reason)
                        }
                    }
                    try await ResponsesWebSocketSession(
                        responder: responder, request: request, limits: limits, upstreamTransport: upstreamTransport
                    )
                    .run(messages: messages) { data in
                        try await outbound.writeTextMessage(responseText(data))
                    }
                }
            }
            return GatewayWebSocketChannel(base: channel)
        }
        if let tlsConfiguration {
            return try DualProtocolServerBuilder.make(tlsConfiguration: tlsConfiguration, makeChild: makeChild)
        }
        return HTTPServerBuilder(makeChild)
    }

    package enum MessageError: Error, Equatable {
        case binary
        case tooLarge
        case invalidText
    }

    package static func receiveMessage(
        _ message: WebSocketMessage,
        maximumBytes: Int,
        close: @Sendable (WebSocketErrorCode, String) async throws -> Void
    ) async throws -> Data {
        do {
            return try messageData(message, maximumBytes: maximumBytes)
        } catch MessageError.binary {
            try await close(.unacceptableData, "Text messages are required")
            throw MessageError.binary
        } catch {
            try await close(.messageTooLarge, "Message is too large")
            throw error
        }
    }

    /// The library bounds fragmented messages while reading. Check completed
    /// messages too, including messages delivered as a single frame.
    package static func messageData(_ message: WebSocketMessage, maximumBytes: Int) throws -> Data {
        guard case .text(let text) = message else {
            throw MessageError.binary
        }
        guard text.utf8.count <= maximumBytes else {
            throw MessageError.tooLarge
        }
        return Data(text.utf8)
    }

    package static func responseText(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MessageError.invalidText
        }
        return text
    }
}

/// Handshake checks happen before Hummingbird switches away from HTTP and before
/// a session can execute requests. Browser origins retain the HTTP gateway ban.
package struct GatewayWebSocketHandshakePolicy: Sendable {
    private let authorityPolicy: GatewayAuthorityPolicy

    package init(requiredAuthorityPort: Int?) {
        authorityPolicy = GatewayAuthorityPolicy(requiredAuthorityPort)
    }

    package func allows(_ head: HTTPRequest) -> Bool {
        guard head.method == .get,
            GatewayRoute.resolve(URI(head.path ?? "").path) == .responses,
            head.headerFields[.origin] == nil,
            let authority = head.authority,
            authorityPolicy.allows(authority),
            tokens(head.headerFields[.connection]).contains("upgrade"),
            tokens(head.headerFields[.upgrade]).contains("websocket"),
            head.headerFields[.secWebSocketVersion] == "13",
            let key = head.headerFields[.secWebSocketKey],
            let decodedKey = Data(base64Encoded: key),
            decodedKey.count == 16
        else {
            return false
        }
        return true
    }

    private func tokens(_ value: String?) -> Set<String> {
        Set(
            (value ?? "").split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
    }
}

/// WSCore trace logs include frame payload prefixes. Clamp only this transport's
/// logger so raising application verbosity cannot expose client content.
struct GatewayWebSocketChannel: ServerChildChannel {
    typealias Value = HTTP1WebSocketUpgradeChannel.Value

    let base: HTTP1WebSocketUpgradeChannel

    func setup(channel: any Channel, logger: Logger) -> EventLoopFuture<Value> {
        base.setup(channel: channel, logger: Self.metadataLogger(logger))
    }

    func handle(value: Value, logger: Logger) async {
        await withTaskCancellationHandler {
            await base.handle(value: value, logger: Self.metadataLogger(logger))
        } onCancel: {
            // This also releases a connection still waiting for its first HTTP
            // request, whose negotiation future is not task-cancellable.
            value.channel.close(promise: nil)
        }
    }

    static func metadataLogger(_ logger: Logger) -> Logger {
        var logger = logger
        logger.logLevel = max(logger.logLevel, .info)
        return logger
    }
}
