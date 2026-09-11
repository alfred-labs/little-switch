import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Responses provider state transport edges")
struct ProviderStateResponseEdgeTests {
    private let providerID = UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16))

    @Test("A large upstream chunk drains bounded records before requesting the next chunk")
    func retainedChunkBackpressure() async throws {
        let frame = Data("data: one\n\n".utf8)
        let later = Data("data: two\n\n".utf8)
        let source = DemandTrackedBodySequence(chunks: [
            Data(String(repeating: "data: one\n\n", count: 24).utf8), later,
        ])
        let tagged = try await tag(source, maximumBytes: 16)
        var iterator = tagged.body.makeAsyncIterator()
        for _ in 0..<24 {
            #expect(try await iterator.next() == ByteBuffer(bytes: frame))
            #expect(await source.nextCallCount == 1)
        }
        #expect(try await iterator.next() == ByteBuffer(bytes: later))
        #expect(await source.nextCallCount == 2)
        #expect(try await iterator.next() == nil)
        #expect(await source.nextCallCount == 3)
    }

    @Test("Cancellation discards already decoded records before any additional upstream read")
    func bufferedCancellation() async throws {
        let first = Data("data: one\n\n".utf8)
        let source = DemandTrackedBodySequence(chunks: [first + Data("data: two\n\n".utf8)])
        let tagged = try await tag(source, maximumBytes: 64)
        let task = Task<Void, Error> {
            var iterator = tagged.body.makeAsyncIterator()
            let received = try await iterator.next()
            #expect(received == ByteBuffer(bytes: first))
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await iterator.next() }
            let finished = try await iterator.next()
            #expect(finished == nil)
        }
        try await task.value
        #expect(await source.nextCallCount == 1)
    }

    @Test("Already cancelled requests do not inspect JSON or SSE bodies", arguments: [false, true])
    func cancelledConstruction(streaming: Bool) async throws {
        let source = DemandTrackedBodySequence(chunks: [Data("{}".utf8)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) {
                try await tag(source, maximumBytes: 64, streaming: streaming)
            }
        }
        await task.value
        #expect(await source.nextCallCount == 0)
    }

    @Test("Malformed, incomplete and oversized streams terminate permanently")
    func malformedStreams() async throws {
        let fixtures: [(Data, ServerSentEventDecoder.Error)] = [
            (Data([0xFF, 0x0A, 0x0A]), .invalidUTF8),
            (Data([0xFF]), .invalidUTF8),
            (Data("data: unfinished".utf8), .incompleteFrame),
            (Data(("data: " + String(repeating: "x", count: 100)).utf8), .frameTooLarge),
        ]
        for (wire, expected) in fixtures {
            let source = DemandTrackedBodySequence(chunks: [wire])
            let tagged = try await tag(source, maximumBytes: 32)
            var iterator = tagged.body.makeAsyncIterator()
            await #expect(throws: expected) { try await iterator.next() }
            let reads = await source.nextCallCount
            #expect(try await iterator.next() == nil)
            #expect(await source.nextCallCount == reads)
        }
    }

    @Test("Oversized JSON and upstream JSON failures retain their errors")
    func jsonFailures() async throws {
        let oversized = DemandTrackedBodySequence(chunks: [Data(repeating: 0x20, count: 65)])
        await #expect(throws: NIOTooManyBytesError.self) {
            try await tag(oversized, maximumBytes: 64, streaming: false)
        }
        let failed = DemandTrackedBodySequence(chunks: [], termination: .failure)
        await #expect(throws: GatewayTestError.privateFailure) {
            try await tag(failed, maximumBytes: 64, streaming: false)
        }
        let cancelled = DemandTrackedBodySequence(chunks: [], termination: .cancellation)
        await #expect(throws: CancellationError.self) {
            try await tag(cancelled, maximumBytes: 64, streaming: false)
        }
        #expect(await oversized.nextCallCount == 1)
        #expect(await failed.nextCallCount == 1)
        #expect(await cancelled.nextCallCount == 1)
    }

    @Test("Cancellation after JSON EOF wins over a successfully collected payload")
    func cancellationAtJSONEnd() async throws {
        let source = DemandTrackedBodySequence(chunks: [Data("{}".utf8)], gatedNextCall: 1)
        let task = Task {
            _ = await #expect(throws: CancellationError.self) {
                try await tag(source, maximumBytes: 64, streaming: false)
            }
        }
        await source.waitForNextCallCount(2)
        task.cancel()
        await source.releaseGate()
        await task.value
        #expect(await source.nextCallCount == 2)
    }

    @Test("The largest valid limit is accepted and error responses bypass invalid limits")
    func boundsAtEntry() async throws {
        let bytes = Data("{}".utf8)
        let source = DemandTrackedBodySequence(chunks: [bytes])
        let tagged = try await tag(source, maximumBytes: Int.max - 4, streaming: false)
        #expect(try await tagged.body.collect(upTo: 64) == ByteBuffer(bytes: bytes))
        let response = HTTPClientResponse(
            status: .badGateway, headers: ["content-length": "2"], body: .bytes(ByteBuffer(bytes: bytes)))
        let unchanged = try await ResponsesProviderStateResponse.tagged(
            response, providerID: providerID, maximumBytes: 0)
        #expect(unchanged.headers == response.headers)
        #expect(unchanged.status == response.status)
        #expect(try await unchanged.body.collect(upTo: 64) == ByteBuffer(bytes: bytes))
    }

    private func tag(
        _ source: DemandTrackedBodySequence, maximumBytes: Int, streaming: Bool = true
    ) async throws -> HTTPClientResponse {
        try await ResponsesProviderStateResponse.tagged(
            HTTPClientResponse(
                status: .ok,
                headers: ["content-type": streaming ? "TEXT/EVENT-STREAM; charset=utf-8" : "application/json"],
                body: .stream(source)),
            providerID: providerID,
            maximumBytes: maximumBytes)
    }
}
