import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore

package enum ResponsesProviderStateResponse {
    package static func tagged(
        _ response: HTTPClientResponse, providerID: UUID, maximumBytes: Int
    ) async throws -> HTTPClientResponse {
        guard (200..<300).contains(response.status.code) else { return response }
        try Task.checkCancellation()
        guard maximumBytes > 0, maximumBytes <= Int.max - 4 else { throw ResponsesProviderState.Error.invalidState }
        var result = response
        if response.headers["content-type"].contains(where: { $0.lowercased().contains("text/event-stream") }) {
            result.body = .stream(
                ResponsesProviderStateStream(body: response.body, providerID: providerID, maximumBytes: maximumBytes))
        } else {
            let buffer = try await response.body.collect(upTo: maximumBytes)
            try Task.checkCancellation()
            let tagged = try ResponsesProviderState.tag(
                response: Data(buffer.readableBytesView), providerID: providerID)
            guard tagged.count <= maximumBytes else { throw ResponsesProviderState.Error.invalidState }
            result.body = .bytes(ByteBuffer(bytes: tagged))
        }
        result.headers.remove(name: "content-length")
        return result
    }
}

private struct ResponsesProviderStateStream: AsyncSequence, Sendable {
    let body: HTTPClientResponse.Body
    let providerID: UUID
    let maximumBytes: Int

    enum Phase { case reading, draining, finished }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(upstream: body.makeAsyncIterator(), providerID: providerID, maximumBytes: maximumBytes)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var upstream: HTTPClientResponse.Body.AsyncIterator
        let providerID: UUID
        let maximumBytes: Int
        var decoder: ServerSentEventDecoder
        var pending = Data()
        var pendingOffset = 0
        var frames: ArraySlice<ServerSentEventFrame> = []
        var incoming: ByteBuffer?
        var phase = Phase.reading

        init(upstream: HTTPClientResponse.Body.AsyncIterator, providerID: UUID, maximumBytes: Int) {
            self.upstream = upstream
            self.providerID = providerID
            self.maximumBytes = maximumBytes
            decoder = ServerSentEventDecoder(maximumFrameBytes: maximumBytes)
        }

        mutating func next() async throws -> ByteBuffer? {
            do {
                while phase != .finished {
                    try Task.checkCancellation()
                    if let ready = try takeReady() { return ready }
                    if phase == .draining {
                        phase = .finished
                        break
                    }
                    if incoming == nil { incoming = try await upstream.next() }
                    try Task.checkCancellation()
                    guard var chunk = incoming else {
                        frames = ArraySlice(try decoder.finish())
                        phase = .draining
                        continue
                    }
                    let length = Swift.min(chunk.readableBytes, maximumBytes + 4 - pending.count)
                    var slice = chunk
                    slice.moveWriterIndex(to: slice.readerIndex + length)
                    chunk.moveReaderIndex(forwardBy: length)
                    incoming = chunk.readableBytes == 0 ? nil : chunk
                    pending.append(contentsOf: slice.readableBytesView)
                    frames = ArraySlice(try decoder.append(slice))
                }
                return nil
            } catch {
                phase = .finished
                incoming = nil
                pending.removeAll()
                frames.removeAll()
                throw error
            }
        }

        private mutating func takeReady() throws -> ByteBuffer? {
            guard pendingOffset < decoder.consumedBytes else { return nil }
            guard let frame = frames.first else { return takeRaw(decoder.consumedBytes - pendingOffset) }
            let (source, range) = try ServerSentEventDataRewriter.originalSource(of: frame)
            if range.lowerBound > pendingOffset { return takeRaw(range.lowerBound - pendingOffset) }
            let count = range.upperBound - pendingOffset
            let result = try ServerSentEventDataRewriter.rewrite(
                Data(pending.prefix(count)), sourceOffset: pendingOffset, frames: [frame]
            ) {
                try ResponsesProviderState.tag(response: $0, providerID: providerID)
            }
            let separatorBytes = range.count - source.count
            guard result.count - separatorBytes <= maximumBytes else { throw ResponsesProviderState.Error.invalidState }
            frames.removeFirst()
            discard(count)
            return ByteBuffer(bytes: result)
        }

        private mutating func takeRaw(_ count: Int) -> ByteBuffer {
            let bytes = ByteBuffer(bytes: pending.prefix(count))
            discard(count)
            return bytes
        }

        private mutating func discard(_ count: Int) {
            pending.removeFirst(count)
            pendingOffset += count
        }
    }
}
