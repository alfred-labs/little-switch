import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Responses provider state response")
struct ProviderStateResponseTests {
    private let providerID = UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16))
    private let reasoning = Data(#"{"item":{"type":"reasoning","id":"rs_1","summary":[]}}"#.utf8)

    @Test("A transformed stream preserves metadata and separators at every byte boundary")
    func transformedStreamBytes() async throws {
        let prefix = ": keep\r\nid: 17\r\nretry: 500\revent: response.output_item.added\ndata: "
        let suffix = "\r\n\r\n: tail\r\rdata: [DONE]\n\n"
        let wire = Data(prefix.utf8) + reasoning + Data(suffix.utf8)
        let expected =
            Data(prefix.utf8) + (try ResponsesProviderState.tag(response: reasoning, providerID: providerID))
            + Data(suffix.utf8)
        for chunks in [[wire], wire.map { Data([$0]) }] {
            let source = DemandTrackedBodySequence(chunks: chunks)
            let tagged = try await tag(source, maximumBytes: 4_096)
            #expect(try await collect(tagged.body) == expected)
            #expect(await source.nextCallCount == chunks.count + 1)
        }
    }

    @Test("Coalescing individually bounded frames does not change whether the stream succeeds")
    func coalescedFrameBounds() async throws {
        let frame = Data("data: ".utf8) + reasoning + Data("\n\n".utf8)
        let expectedFrame =
            Data("data: ".utf8)
            + (try ResponsesProviderState.tag(response: reasoning, providerID: providerID)) + Data("\n\n".utf8)
        for chunks in [[frame + frame], [frame, frame]] {
            let tagged = try await tag(DemandTrackedBodySequence(chunks: chunks), maximumBytes: expectedFrame.count)
            #expect(try await collect(tagged.body) == expectedFrame + expectedFrame)
        }
    }

    @Test("Invalid bounds fail before creating a stream", arguments: [-1, 0, Int.max - 3, Int.max])
    func invalidBounds(maximumBytes: Int) async throws {
        let source = DemandTrackedBodySequence(chunks: [])
        await #expect(throws: ResponsesProviderState.Error.invalidState) {
            try await tag(source, maximumBytes: maximumBytes)
        }
        #expect(await source.nextCallCount == 0)
    }

    @Test("Streaming is lazy and abandonment never drains another upstream chunk")
    func lazyStream() async throws {
        let first = Data("data: plain\n\n".utf8)
        let source = DemandTrackedBodySequence(chunks: [first, Data("data: later\n\n".utf8)])
        let tagged = try await tag(source, maximumBytes: 64)
        #expect(await source.nextCallCount == 0)
        var iterator = tagged.body.makeAsyncIterator()
        #expect(try await iterator.next() == ByteBuffer(bytes: first))
        #expect(await source.nextCallCount == 1)
    }

    @Test("Provider failures and cancellation terminate the iterator without another read")
    func streamFailures() async throws {
        for cancelled in [false, true] {
            let source = DemandTrackedBodySequence(chunks: [], termination: cancelled ? .cancellation : .failure)
            let tagged = try await tag(source, maximumBytes: 64)
            var iterator = tagged.body.makeAsyncIterator()
            if !cancelled {
                await #expect(throws: GatewayTestError.privateFailure) { try await iterator.next() }
            } else {
                await #expect(throws: CancellationError.self) { try await iterator.next() }
            }
            #expect(try await iterator.next() == nil)
            #expect(await source.nextCallCount == 1)
        }
    }

    @Test("Cancellation after a suspended upstream read never publishes its bytes")
    func cancellationWhileReading() async throws {
        let source = DemandTrackedBodySequence(chunks: [Data("data: plain\n\n".utf8)], gatedNextCall: 0)
        let tagged = try await tag(source, maximumBytes: 64)
        let task = Task {
            var iterator = tagged.body.makeAsyncIterator()
            do {
                _ = try await iterator.next()
                return false
            } catch is CancellationError {
                return try await iterator.next() == nil
            }
        }
        await source.waitForNextCallCount(1)
        task.cancel()
        await source.releaseGate()
        #expect(try await task.value)
        #expect(await source.nextCallCount == 1)
    }

    @Test("An expanded frame that exceeds the limit fails without reading more")
    func expandedFrameLimit() async throws {
        let frame = Data("data: ".utf8) + reasoning + Data("\n\n".utf8)
        let source = DemandTrackedBodySequence(chunks: [frame, Data("data: later\n\n".utf8)])
        let tagged = try await tag(source, maximumBytes: frame.count)
        var iterator = tagged.body.makeAsyncIterator()
        await #expect(throws: ResponsesProviderState.Error.invalidState) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(await source.nextCallCount == 1)
    }

    @Test("Empty chunks, comments and trailing whitespace survive EOF exactly")
    func eofFormatting() async throws {
        for wire in ["", " \t\r\n", ": comment\r\r", "data: plain\r\n\r"] {
            let source = DemandTrackedBodySequence(chunks: [Data()] + wire.utf8.map { Data([$0]) })
            let tagged = try await tag(source, maximumBytes: 64)
            var iterator = tagged.body.makeAsyncIterator()
            var received = Data()
            while let chunk = try await iterator.next() { received.append(contentsOf: chunk.readableBytesView) }
            #expect(received == Data(wire.utf8))
            #expect(try await iterator.next() == nil)
            #expect(await source.nextCallCount == wire.utf8.count + 2)
        }
    }

    @Test("JSON tagging is bounded and updates the response length metadata")
    func jsonResponse() async throws {
        let source = DemandTrackedBodySequence(chunks: [reasoning])
        let response = HTTPClientResponse(
            status: .ok, headers: ["content-type": "application/json", "content-length": "99"], body: .stream(source)
        )
        let tagged = try await ResponsesProviderStateResponse.tagged(
            response, providerID: providerID, maximumBytes: 4_096)
        #expect(tagged.headers["content-length"].isEmpty)
        let expected = try ResponsesProviderState.tag(response: reasoning, providerID: providerID)
        #expect(try await collect(tagged.body) == expected)
        #expect(await source.nextCallCount == 2)
        let bounded = HTTPClientResponse(status: .ok, headers: [:], body: .bytes(ByteBuffer(bytes: reasoning)))
        await #expect(throws: ResponsesProviderState.Error.invalidState) {
            try await ResponsesProviderStateResponse.tagged(
                bounded, providerID: providerID, maximumBytes: reasoning.count)
        }
    }

    @Test("Error responses retain their headers and body without being read")
    func errorResponse() async throws {
        let source = DemandTrackedBodySequence(chunks: [Data("failure".utf8)])
        let response = HTTPClientResponse(
            status: .badGateway,
            headers: ["content-type": "application/json", "content-length": "7"],
            body: .stream(source)
        )
        let tagged = try await ResponsesProviderStateResponse.tagged(
            response, providerID: providerID, maximumBytes: 4_096)
        #expect(tagged.status == response.status)
        #expect(tagged.headers == response.headers)
        #expect(await source.nextCallCount == 0)
        #expect(try await collect(tagged.body) == Data("failure".utf8))
    }

    private func tag(_ source: DemandTrackedBodySequence, maximumBytes: Int) async throws -> HTTPClientResponse {
        try await ResponsesProviderStateResponse.tagged(
            HTTPClientResponse(status: .ok, headers: ["content-type": "text/event-stream"], body: .stream(source)),
            providerID: providerID,
            maximumBytes: maximumBytes
        )
    }

    private func collect(_ body: HTTPClientResponse.Body) async throws -> Data {
        Data(try await body.collect(upTo: 64 * 1_024).readableBytesView)
    }
}
