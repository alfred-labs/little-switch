import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOWebSocket
@_spi(WSInternal) import WSCore

struct WebSocketOperationFailure: Error {
    let underlying: any Error
}

enum WSCoreConnectionDriver {
    static func run(
        channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>,
        handshake: HTTPResponseHead,
        control: WebSocketConnectionControl,
        configuration: UpstreamWebSocketConfiguration,
        operation: @escaping @Sendable (UpstreamWebSocketConnection) async throws -> Void
    ) async throws {
        var logger = Logger(label: "LittleSwitch.WebSocket")
        logger.logLevel = .info
        let ping: AutoPingSetup = configuration.pingInterval.map { .enabled(timePeriod: $0) } ?? .disabled
        _ = try await WebSocketHandler.handle(
            type: .client,
            configuration: .init(
                extensions: [],
                autoPing: ping,
                closeTimeout: configuration.closeTimeout,
                validateUTF8: true,
                maxFrameSize: configuration.outboundFragmentBytes),
            asyncChannel: channel,
            context: Context(logger: logger)
        ) { inbound, outbound, _ in
            try await control.eventLoop.submit { try control.state.value.installWriter(control: control) }.get()
            let writer = WebSocketMessageWriter(control: control)
            let connection = UpstreamWebSocketConnection(
                handshake: handshake,
                inbound: Incoming(
                    stream: inbound, control: control, maximumBytes: configuration.maximumInboundMessageBytes),
                outbound: writer)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await writer.run { command in
                        switch command {
                        case .message(.text(let text)):
                            try await writeMessage(
                                ByteBuffer(string: text),
                                opcode: .text,
                                outbound: outbound,
                                control: control,
                                fragmentBytes: configuration.outboundFragmentBytes)
                        case .message(.binary(let data)):
                            try await writeMessage(
                                ByteBuffer(bytes: data),
                                opcode: .binary,
                                outbound: outbound,
                                control: control,
                                fragmentBytes: configuration.outboundFragmentBytes)
                        // swiftlint:disable:next pattern_matching_keywords
                        case .close(let code, let reason):
                            try await outbound.close(.init(codeNumber: Int(code)), reason: reason)
                            let written = control.eventLoop.flatSubmit { control.state.value.waitForLocalCloseWrite() }
                            try await written.get()
                        }
                    }
                }
                group.addTask {
                    do {
                        try await operation(connection)
                        try await writer.finishOperation()
                    } catch {
                        let failure = WebSocketOperationFailure(underlying: error)
                        control.abort(failure)
                        throw failure
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    private static func writeMessage(
        _ buffer: ByteBuffer,
        opcode: WebSocketOpcode,
        outbound: WebSocketOutboundWriter,
        control: WebSocketConnectionControl,
        fragmentBytes: Int
    ) async throws {
        var buffer = buffer
        var opcode = opcode
        repeat {
            let acknowledged = try await control.eventLoop.submit { control.state.value.beginDataWrite() }.get()
            // Every closing transition has already resolved the active ticket.
            guard let acknowledged else { return }
            let length = min(buffer.readableBytes, fragmentBytes)
            guard let fragment = buffer.readSlice(length: length) else {
                throw UpstreamWebSocketFailure(kind: .writeFailed)
            }
            try await outbound.write(
                .custom(.init(fin: buffer.readableBytes == 0, opcode: opcode, data: fragment)))
            // NIOAsyncChannel's write only yields the frame. Keep the ticket and
            // queue budget until the downstream socket write has completed.
            try await acknowledged.get()
            opcode = .continuation
        } while buffer.readableBytes > 0
    }

    private struct Context: WebSocketContext {
        let logger: Logger
    }

    private struct Incoming: UpstreamWebSocketInbound {
        let stream: WebSocketInboundStream
        let control: WebSocketConnectionControl
        let maximumBytes: Int

        func consume(
            _ onMessage: @escaping @Sendable (UpstreamWebSocketMessage) async throws -> Void
        ) async throws -> UpstreamWebSocketPeerClose {
            try await control.eventLoop.submit { try control.state.value.claimReader() }.get()
            return try await withTaskCancellationHandler {
                var iterator = stream.makeAsyncIterator()
                while true {
                    let message: UpstreamWebSocketMessage?
                    do {
                        message = try await nextMessage(iterator: &iterator)
                    } catch {
                        let failure = await control.normalized(error)
                        control.abort(failure)
                        throw failure
                    }
                    guard let message else { break }
                    try await onMessage(message)
                }
                let closeWrite = control.eventLoop.flatSubmit { control.state.value.waitForCloseWrite() }
                try await closeWrite.get()
                return try await control.eventLoop.submit { try control.state.value.receivedPeerClose() }.get()
            } onCancel: {
                control.abort(CancellationError())
            }
        }

        private func nextMessage(
            iterator: inout WebSocketInboundStream.AsyncIterator
        ) async throws -> UpstreamWebSocketMessage? {
            var payload = ByteBuffer()
            var opcode: WebSocketDataFrame.Opcode?
            while let frame = try await iterator.next() {
                if opcode == nil {
                    guard frame.opcode != .continuation else {
                        throw UpstreamWebSocketFailure(kind: .protocolViolation)
                    }
                    opcode = frame.opcode
                } else {
                    guard frame.opcode == .continuation else {
                        throw UpstreamWebSocketFailure(kind: .protocolViolation)
                    }
                }
                guard frame.data.readableBytes <= maximumBytes - payload.readableBytes else {
                    throw UpstreamWebSocketFailure(kind: .messageTooLarge)
                }
                payload.writeImmutableBuffer(frame.data)
                if frame.fin {
                    if opcode == .text {
                        guard let text = String(bytes: payload.readableBytesView, encoding: .utf8) else {
                            throw UpstreamWebSocketFailure(kind: .protocolViolation)
                        }
                        return .text(text)
                    }
                    return .binary(Data(payload.readableBytesView))
                }
            }
            return nil
        }
    }
}
