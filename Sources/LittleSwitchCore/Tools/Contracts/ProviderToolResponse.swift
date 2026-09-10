import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore

/// Enforces ownership before successful provider bytes reach public adapters.
package enum ProviderToolResponse {
    /// Reports collected JSON on validation rejection, or the bounded SSE prefix
    /// retained when iteration fails. Previously yielded and unread bytes are
    /// excluded; this callback does not promise a complete rejected response.
    package static func validated(
        _ response: HTTPClientResponse,
        requestBody: Data,
        wire: ProviderToolContract.Wire,
        maximumBytes: Int,
        declaredToolBindings: [String: ResponsesToolNamespaces.Binding] = [:],
        onRejectedBytes: (@Sendable (Data) -> Void)? = nil
    ) async throws -> HTTPClientResponse {
        guard (200..<300).contains(response.status.code) else { return response }
        try Task.checkCancellation()
        guard maximumBytes > 0, maximumBytes <= Int.max - 4 else { throw ProviderToolContract.Error.invalidResponse }
        let contract = try ProviderToolContract(
            wire: wire,
            requestBody: requestBody,
            declaredToolBindings: declaredToolBindings
        )
        var validated = response
        if response.headers["content-type"].contains(where: { $0.lowercased().contains("text/event-stream") }) {
            validated.body = .stream(
                ProviderToolValidatedStream(
                    body: response.body,
                    contract: contract,
                    maximumBytes: maximumBytes,
                    onRejectedBytes: onRejectedBytes))
        } else {
            let bytes = try await response.body.collect(upTo: maximumBytes)
            try Task.checkCancellation()
            let data = Data(bytes.readableBytesView)
            do {
                try contract.validateBuffered(data)
            } catch {
                onRejectedBytes?(data)
                throw error
            }
            validated.body = .bytes(bytes)
        }
        return validated
    }
}

private struct ProviderToolValidatedStream: AsyncSequence, Sendable {
    let body: HTTPClientResponse.Body
    let contract: ProviderToolContract
    let maximumBytes: Int
    let onRejectedBytes: (@Sendable (Data) -> Void)?

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            upstream: body.makeAsyncIterator(),
            contract: contract,
            maximumBytes: maximumBytes,
            onRejectedBytes: onRejectedBytes)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var upstream: HTTPClientResponse.Body.AsyncIterator
        private var contract: ProviderToolContract
        private var decoder: ServerSentEventDecoder
        private let maximumBytes: Int
        private let onRejectedBytes: (@Sendable (Data) -> Void)?
        private var incoming: ByteBuffer?
        private var pending = Data()
        private var exhausted = false

        init(
            upstream: HTTPClientResponse.Body.AsyncIterator,
            contract: ProviderToolContract,
            maximumBytes: Int,
            onRejectedBytes: (@Sendable (Data) -> Void)?
        ) {
            self.upstream = upstream
            self.contract = contract
            self.maximumBytes = maximumBytes
            self.onRejectedBytes = onRejectedBytes
            decoder = ServerSentEventDecoder(maximumFrameBytes: maximumBytes)
        }

        mutating func next() async throws -> ByteBuffer? {
            guard !exhausted else { return nil }
            do {
                while var chunk = try await nextChunk() {
                    let length = Swift.min(chunk.readableBytes, maximumBytes + 4 - pending.count)
                    var slice = chunk
                    slice.moveWriterIndex(to: slice.readerIndex + length)
                    chunk.moveReaderIndex(forwardBy: length)
                    incoming = chunk.readableBytes == 0 ? nil : chunk
                    pending.append(contentsOf: slice.readableBytesView)
                    let before = decoder.consumedBytes
                    for frame in try decoder.append(slice) { try contract.validateFrame(frame) }
                    let consumed = decoder.consumedBytes - before
                    if consumed > 0 { return take(consumed) }
                }
                return try finish()
            } catch {
                // An iterator cannot expose retained bytes after validation fails.
                exhausted = true
                incoming = nil
                if !pending.isEmpty { onRejectedBytes?(pending) }
                pending.removeAll()
                throw error
            }
        }

        private mutating func nextChunk() async throws -> ByteBuffer? {
            try Task.checkCancellation()
            if incoming == nil { incoming = try await upstream.next() }
            try Task.checkCancellation()
            return incoming
        }

        private mutating func finish() throws -> ByteBuffer? {
            for frame in try decoder.finish() { try contract.validateFrame(frame) }
            try contract.finish()
            exhausted = true
            return pending.isEmpty ? nil : take(pending.count)
        }

        private mutating func take(_ count: Int) -> ByteBuffer {
            let bytes = ByteBuffer(bytes: pending.prefix(count))
            pending.removeFirst(count)
            return bytes
        }
    }
}
