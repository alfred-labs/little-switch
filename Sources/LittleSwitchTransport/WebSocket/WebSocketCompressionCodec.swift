import HTTPTypes
import NIOWebSocket
import WSCompression
import WSCore

extension WebSocketCompressionNegotiation {
    func makeExtensions(
        maximumBytes: Int,
        control: WebSocketConnectionControl
    ) throws -> [any WebSocketExtension] {
        guard case .perMessageDeflate(let parameters) = self else { return [] }
        let factory = WebSocketExtensionFactory.perMessageDeflate(
            maxWindow: nil, maxDecompressedFrameSize: maximumBytes)
        let builders: [any WebSocketExtensionBuilder] = [factory.build()]
        let extensions = try builders.buildClientExtensions(from: [.secWebSocketExtensions: parameters.header])
        let inflater = try WebSocketInflater(
            maximumBytes: maximumBytes,
            windowBits: parameters.receiveWindow,
            noContextTakeover: parameters.receiveNoContextTakeover)
        return extensions.map { WebSocketCompressionCodec(base: $0, inflater: inflater, control: control) }
    }
}

/// WSCore handles its own decoding errors as close frames, rather than throwing
/// them to the consumer. Preserve a typed terminal failure through the existing
/// transport owner so malformed/oversized deflate cannot look like clean EOF.
private struct WebSocketCompressionCodec: WebSocketExtension {
    let base: any WebSocketExtension
    let inflater: WebSocketInflater
    let control: WebSocketConnectionControl

    var name: String { base.name }
    var reservedBits: WebSocketFrame.ReservedBits { base.reservedBits }

    func processReceivedFrame(
        _ frame: WebSocketFrame,
        context: WebSocketExtensionContext
    ) async throws -> WebSocketFrame {
        do {
            return try await inflater.process(frame)
        } catch {
            let failure = (error as? UpstreamWebSocketFailure) ?? UpstreamWebSocketFailure(kind: .protocolViolation)
            control.abort(failure)
            throw failure
        }
    }

    func processFrameToSend(
        _ frame: WebSocketFrame,
        context: WebSocketExtensionContext
    ) async throws -> WebSocketFrame {
        do {
            return try await base.processFrameToSend(frame, context: context)
        } catch {
            let failure = UpstreamWebSocketFailure(kind: .writeFailed)
            control.abort(failure)
            throw failure
        }
    }

    func shutdown() async { await base.shutdown() }
}
