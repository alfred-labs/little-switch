import AsyncHTTPClient
import Foundation
import NIOCore
import os

package struct GatewayModelExchange: Sendable {
    let response: HTTPClientResponse
    let trace: GatewayUpstreamResponseTrace
}

/// One ordered, bounded byte trace shared by validation and the body consumer.
/// The consumer finishes it in a defer, including cancellation and writer errors.
package final class GatewayUpstreamResponseTrace: Sendable {
    fileprivate enum Origin: Sendable { case upstream, consumer }

    private struct State: Sendable {
        var chunks = TrafficChunkCoalescer()
        var finished = false
        var origin = Origin.consumer
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let recorder: any TrafficRecording
    private let eventID: UUID
    private let attempt: Int

    package init(recorder: any TrafficRecording, eventID: UUID, attempt: Int) {
        self.recorder = recorder
        self.eventID = eventID
        self.attempt = attempt
    }

    package func append(_ bytes: Data) {
        append(bytes, origin: .consumer)
    }

    fileprivate func append(_ bytes: Data, origin: Origin) {
        state.withLock { state in
            guard !state.finished, state.origin == origin else { return }
            record(state.chunks.append(bytes))
        }
    }

    package func finish() {
        state.withLock { state in
            guard !state.finished else { return }
            state.finished = true
            record(state.chunks.flush())
        }
    }

    package func collect(_ body: HTTPClientResponse.Body, upTo maximumBytes: Int) async throws -> Data {
        defer { finish() }
        let buffer = try await observing(body).collect(upTo: maximumBytes)
        return Data(buffer.readableBytesView)
    }

    package func observing(_ body: HTTPClientResponse.Body) -> HTTPClientResponse.Body {
        .stream(GatewayTraceBody(body: body, trace: self, origin: .consumer))
    }

    /// An adapter may change bytes before the consumer sees them. In that case
    /// only the upstream observer records, while the consumer still owns finish.
    package func observingUpstream(_ body: HTTPClientResponse.Body) -> HTTPClientResponse.Body {
        state.withLock { $0.origin = .upstream }
        return .stream(GatewayTraceBody(body: body, trace: self, origin: .upstream))
    }

    private func record(_ chunks: [Data]) {
        recordTrafficChunks(chunks, target: .upstream(attempt: attempt), recorder: recorder, eventID: eventID)
    }
}

private struct GatewayTraceBody: AsyncSequence, Sendable {
    let body: HTTPClientResponse.Body
    let trace: GatewayUpstreamResponseTrace
    let origin: GatewayUpstreamResponseTrace.Origin

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(upstream: body.makeAsyncIterator(), trace: trace, origin: origin)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var upstream: HTTPClientResponse.Body.AsyncIterator
        let trace: GatewayUpstreamResponseTrace
        let origin: GatewayUpstreamResponseTrace.Origin

        mutating func next() async throws -> ByteBuffer? {
            guard let buffer = try await upstream.next() else { return nil }
            trace.append(Data(buffer.readableBytesView), origin: origin)
            return buffer
        }
    }
}

extension GatewayResponder {
    package func upstreamResponseTrace(eventID: UUID, attempt: Int) -> GatewayUpstreamResponseTrace {
        GatewayUpstreamResponseTrace(recorder: trafficRecorder, eventID: eventID, attempt: attempt)
    }
}
