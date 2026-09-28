import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore

extension GatewayResponder {
    /// Native Responses bytes remain opaque to the adapters, but HTTP 200 only
    /// opens an SSE exchange. Observe its error events before recording success.
    package func nativeResponsesStream(
        _ upstream: HTTPClientResponse, eventID: UUID, requestedStreaming: Bool = false
    ) -> Response {
        recordUpstreamResponseHead(eventID: eventID, attempt: 0, response: upstream)
        let contentTypes = upstream.headers[HTTPField.Name.contentType.rawName]
        // The native Codex backend can omit Content-Type on a successful SSE
        // response. In that case the request's stream flag defines the format.
        // Keep explicit media types and HTTP errors authoritative.
        let streaming =
            contentTypes.contains { $0.lowercased().contains("text/event-stream") }
            || (contentTypes.isEmpty && requestedStreaming)
        guard (200..<300).contains(upstream.status.code),
            streaming
        else { return streamingResponse(upstream, eventID: eventID, attempt: 0) }

        var headers = gatewayResponseHeaders(upstream.headers)
        if contentTypes.isEmpty { headers[.contentType] = "text/event-stream" }
        let trace = upstreamResponseTrace(eventID: eventID, attempt: 0)
        let maximumBytes = maximumErrorBytes
        let recorder = trafficRecorder
        return Response(
            status: .init(code: Int(upstream.status.code), reasonPhrase: upstream.status.reasonPhrase),
            headers: headers,
            body: ResponseBody(contentLength: nil) { writer in
                defer { trace.finish() }
                var outcome = NativeResponsesStreamOutcome(maximumBytes: maximumBytes)
                for try await buffer in upstream.body {
                    trace.append(Data(buffer.readableBytesView))
                    try await writer.write(buffer)
                    outcome.append(buffer)
                }
                outcome.finish()
                try await writer.finish(nil)
                if outcome.unavailable {
                    recorder.record(
                        eventID: eventID,
                        action: .annotation(
                            TrafficAnnotation(
                                kind: "native-stream-observation",
                                message: "Native stream outcome inspection was limited")))
                }
                if outcome.failed {
                    throw GatewayCommittedStreamFailure(reason: "Native Responses reported failure")
                }
            })
    }
}

private struct NativeResponsesStreamOutcome {
    private var decoder: ServerSentEventDecoder
    private(set) var failed = false
    private(set) var unavailable = false

    init(maximumBytes: Int) {
        decoder = ServerSentEventDecoder(maximumFrameBytes: maximumBytes)
    }

    mutating func append(_ buffer: ByteBuffer) {
        guard !unavailable else { return }
        do {
            for frame in try decoder.append(buffer) { observe(frame) }
        } catch {
            // Observation is bounded; forwarding is not. Release the retained
            // frame and keep relaying the original stream after the limit.
            decoder = ServerSentEventDecoder(maximumFrameBytes: 0)
            unavailable = true
        }
    }

    mutating func finish() {
        guard !unavailable else { return }
        do {
            for frame in try decoder.finish() { observe(frame) }
        } catch {
            unavailable = true
        }
    }

    private mutating func observe(_ frame: ServerSentEventFrame) {
        let payload = try? responsesStreamObject(frame.data)
        switch payload?["type"] as? String ?? frame.event {
        case "error", "response.failed":
            failed = true
        default:
            break
        }
    }
}
