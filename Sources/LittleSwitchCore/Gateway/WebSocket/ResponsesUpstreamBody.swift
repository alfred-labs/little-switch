import AsyncAlgorithms
import NIOCore

/// Acknowledgement occurs when the consumer asks for the next chunk, after the
/// current event passed all wrappers and its public checkpoint was published.
actor ResponsesUpstreamBody: AsyncSequence {
    fileprivate struct Chunk: Sendable {
        let buffer: ByteBuffer
        let acknowledgement: AsyncStream<Void>.Continuation
    }
    private let channel = AsyncThrowingChannel<Chunk, any Error>()
    private var pending: AsyncStream<Void>.Continuation?

    func send(_ buffer: ByteBuffer) async throws {
        let (stream, acknowledgement) = AsyncStream<Void>.makeStream()
        pending = acknowledgement
        await channel.send(Chunk(buffer: buffer, acknowledgement: acknowledgement))
        for await _ in stream {}
        pending = nil
        try Task.checkCancellation()
    }

    func finish() {
        channel.finish()
        pending?.finish()
        pending = nil
    }

    func fail(_ error: any Error) {
        channel.fail(error)
        pending?.finish()
        pending = nil
    }

    nonisolated func makeAsyncIterator() -> AsyncIterator { AsyncIterator(source: channel.makeAsyncIterator()) }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var source: AsyncThrowingChannel<Chunk, any Error>.Iterator
        private var previous: AsyncStream<Void>.Continuation?

        fileprivate init(source: AsyncThrowingChannel<Chunk, any Error>.Iterator) { self.source = source }

        mutating func next() async throws -> ByteBuffer? {
            previous?.finish()
            previous = nil
            guard let chunk = try await source.next() else { return nil }
            previous = chunk.acknowledgement
            return chunk.buffer
        }
    }
}
