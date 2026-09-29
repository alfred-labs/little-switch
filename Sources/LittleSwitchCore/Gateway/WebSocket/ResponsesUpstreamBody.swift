import AsyncAlgorithms
import AsyncHTTPClient
import HTTPTypes
import NIOCore

/// Acknowledgement occurs when the consumer asks for the next chunk, after the
/// current event passed all wrappers and its public checkpoint was published.
actor ResponsesUpstreamBody: AsyncSequence {
    private enum Admission: Sendable {
        case streaming
        case rejected(ResponsesUpstreamRejection)
    }
    private let admission = ResponsesUpstreamReadiness<Admission>()
    private var admitted = false
    fileprivate struct Chunk: Sendable {
        let buffer: ByteBuffer
        let acknowledgement: AsyncStream<Void>.Continuation
    }
    private let channel = AsyncThrowingChannel<Chunk, any Error>()
    private var pending: AsyncStream<Void>.Continuation?

    func response() async throws -> HTTPClientResponse {
        switch try await admission.wait() {
        case .streaming:
            HTTPClientResponse(
                status: .ok, headers: [HTTPField.Name.contentType.rawName: "text/event-stream"], body: .stream(self))
        case .rejected(let rejection):
            HTTPClientResponse(
                status: rejection.status,
                headers: [HTTPField.Name.contentType.rawName: "application/json"],
                body: .bytes(ByteBuffer(bytes: rejection.body)))
        }
    }

    func reject(_ rejection: ResponsesUpstreamRejection) async {
        admitted = true
        finish()
        await admission.resolve(.success(.rejected(rejection)))
    }

    func send(_ buffer: ByteBuffer) async throws {
        if !admitted {
            admitted = true
            await admission.resolve(.success(.streaming))
        }
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

    func fail(_ error: any Error) async {
        channel.fail(error)
        pending?.finish()
        pending = nil
        await admission.resolve(.failure(error))
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
