import AsyncHTTPClient
import Foundation
import HTTPTypes
import LittleSwitchTransport
import NIOCore

package enum CustomToolResponse {
    package static func restored(
        _ response: HTTPClientResponse, projection: CustomToolProjection, maximumBytes: Int
    ) async throws -> HTTPClientResponse {
        guard !projection.isIdentity, (200..<300).contains(response.status.code) else { return response }
        try Task.checkCancellation()
        guard maximumBytes > 0, maximumBytes <= Int.max - 4 else { throw CustomToolProjection.Error.limitExceeded }
        var result = response
        if response.headers[HTTPField.Name.contentType.rawName].contains(where: {
            $0.lowercased().contains("text/event-stream")
        }) {
            result.body = .stream(
                CustomToolResponseStream(body: response.body, projection: projection, maximumBytes: maximumBytes))
        } else {
            let source = try await response.body.collect(upTo: maximumBytes)
            try Task.checkCancellation()
            let restored = try projection.restoreBuffered(Data(source.readableBytesView))
            guard restored.count <= maximumBytes else { throw CustomToolProjection.Error.limitExceeded }
            result.body = .bytes(ByteBuffer(bytes: restored))
        }
        result.headers.remove(name: HTTPField.Name.contentLength.rawName)
        return result
    }
}

private struct CustomToolResponseStream: AsyncSequence, Sendable {
    let body: HTTPClientResponse.Body
    let projection: CustomToolProjection
    let maximumBytes: Int

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(upstream: body.makeAsyncIterator(), projection: projection, maximumBytes: maximumBytes)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var upstream: HTTPClientResponse.Body.AsyncIterator
        var projection: CustomToolStreamProjection
        var decoder: ServerSentEventDecoder
        let maximumBytes: Int
        var pending = Data()
        var offset = 0
        var frames: ArraySlice<ServerSentEventFrame> = []
        var incoming: ByteBuffer?
        var eof = false
        var finished = false

        init(upstream: HTTPClientResponse.Body.AsyncIterator, projection: CustomToolProjection, maximumBytes: Int) {
            self.upstream = upstream
            self.projection = CustomToolStreamProjection(projection: projection, maximumBytes: maximumBytes)
            self.maximumBytes = maximumBytes
            decoder = ServerSentEventDecoder(maximumFrameBytes: maximumBytes)
        }

        mutating func next() async throws -> ByteBuffer? {
            do {
                while !finished {
                    try Task.checkCancellation()
                    if let ready = try takeReady() {
                        if ready.readableBytes > 0 { return ready }
                        continue
                    }
                    if eof {
                        try projection.finish()
                        finished = true
                        return nil
                    }
                    if incoming == nil { incoming = try await upstream.next() }
                    try Task.checkCancellation()
                    guard var chunk = incoming else {
                        frames = ArraySlice(try decoder.finish())
                        eof = true
                        continue
                    }
                    if chunk.readableBytes == 0 {
                        incoming = nil
                        continue
                    }
                    let length = Swift.min(chunk.readableBytes, maximumBytes + 4 - pending.count)
                    guard length > 0 else { throw CustomToolProjection.Error.limitExceeded }
                    guard let slice = chunk.readSlice(length: length) else {
                        throw CustomToolProjection.Error.invalidResponse
                    }
                    incoming = chunk.readableBytes == 0 ? nil : chunk
                    pending.append(contentsOf: slice.readableBytesView)
                    frames = ArraySlice(try decoder.append(slice))
                }
                return nil
            } catch {
                finished = true
                incoming = nil
                pending.removeAll()
                frames.removeAll()
                projection.clear()
                throw error
            }
        }

        private mutating func takeReady() throws -> ByteBuffer? {
            guard offset < decoder.consumedBytes else { return nil }
            guard let frame = frames.first else { return takeRaw(decoder.consumedBytes - offset) }
            let (_, range) = try ServerSentEventDataRewriter.originalSource(of: frame)
            if range.lowerBound > offset { return takeRaw(range.lowerBound - offset) }
            let count = range.upperBound - offset
            let source = Data(pending.prefix(count))
            let result = try CustomToolFrameRewrite.apply(
                projection.consume(frame), frame: frame, source: source, offset: offset)
            guard result.count <= maximumBytes + 4 else { throw CustomToolProjection.Error.limitExceeded }
            frames.removeFirst()
            discard(count)
            return ByteBuffer(bytes: result)
        }

        private mutating func takeRaw(_ count: Int) -> ByteBuffer {
            let result = ByteBuffer(bytes: pending.prefix(count))
            discard(count)
            return result
        }

        private mutating func discard(_ count: Int) {
            pending.removeFirst(count)
            offset += count
        }
    }
}
