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
    private struct State: Sendable {
        var chunks = TrafficChunkCoalescer()
        var finished = false
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
        state.withLock { state in
            guard !state.finished else { return }
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
        .stream(GatewayTraceBody(body: body, trace: self))
    }

    private func record(_ chunks: [Data]) {
        recordTrafficChunks(chunks, target: .upstream(attempt: attempt), recorder: recorder, eventID: eventID)
    }
}

private struct GatewayTraceBody: AsyncSequence, Sendable {
    let body: HTTPClientResponse.Body
    let trace: GatewayUpstreamResponseTrace

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(upstream: body.makeAsyncIterator(), trace: trace)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var upstream: HTTPClientResponse.Body.AsyncIterator
        let trace: GatewayUpstreamResponseTrace

        mutating func next() async throws -> ByteBuffer? {
            guard let buffer = try await upstream.next() else { return nil }
            trace.append(Data(buffer.readableBytesView))
            return buffer
        }
    }
}

extension GatewayResponder {
    package func upstreamResponseTrace(eventID: UUID, attempt: Int) -> GatewayUpstreamResponseTrace {
        GatewayUpstreamResponseTrace(recorder: trafficRecorder, eventID: eventID, attempt: attempt)
    }
}
