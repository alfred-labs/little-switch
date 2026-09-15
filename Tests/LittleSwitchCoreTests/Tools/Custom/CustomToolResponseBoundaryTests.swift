import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom response boundaries")
struct CustomToolResponseBoundaryTests {
    @Test("Invalid bounds fail before consuming upstream", arguments: [0, -1, Int.max])
    func invalidBounds(_ limit: Int) async throws {
        let source = DemandTrackedBodySequence(chunks: [])
        let response = HTTPClientResponse(
            status: .ok, headers: ["content-type": "text/event-stream"], body: .stream(source))
        await #expect(throws: CustomToolProjection.Error.limitExceeded) {
            try await CustomToolResponse.restored(response, projection: projection(), maximumBytes: limit)
        }
        #expect(await source.nextCallCount == 0)
    }

    @Test("A cancelled response never exposes retained bytes")
    func cancellation() async throws {
        let response = HTTPClientResponse(
            status: .ok, headers: ["content-type": "text/event-stream"], body: .stream(CancellingGatewayBodySequence()))
        let restored = try await CustomToolResponse.restored(response, projection: projection(), maximumBytes: 4_096)
        var iterator = restored.body.makeAsyncIterator()
        await #expect(throws: CancellationError.self) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
    }

    @Test("Non-success responses retain bytes and headers without consumption")
    func errorIdentity() async throws {
        let bytes = Data("invalid provider type".utf8)
        let source = DemandTrackedBodySequence(chunks: [bytes])
        let response = HTTPClientResponse(status: .badRequest, headers: ["content-length": "21"], body: .stream(source))
        let restored = try await CustomToolResponse.restored(response, projection: projection(), maximumBytes: 4_096)
        #expect(restored.headers == response.headers)
        #expect(await source.nextCallCount == 0)
        #expect(Data(try await restored.body.collect(upTo: 4_096).readableBytesView) == bytes)
    }

    @Test("Empty transport chunks before, inside and after a frame do not end the stream")
    func emptyChunks() async throws {
        let bytes = Data("data: {\"type\":\"response.completed\",\"response\":{\"output\":[]}}\n\n".utf8)
        let source = DemandTrackedBodySequence(chunks: [
            Data(), Data(bytes.prefix(11)), Data(), Data(bytes.dropFirst(11)), Data(),
        ])
        let response = HTTPClientResponse(
            status: .ok, headers: ["content-type": "text/event-stream"], body: .stream(source))
        let restored = try await CustomToolResponse.restored(response, projection: projection(), maximumBytes: 4_096)
        #expect(Data(try await restored.body.collect(upTo: 4_096).readableBytesView) == bytes)
    }

    private func projection() throws -> CustomToolProjection {
        try CustomToolProjection.prepare(
            body: Data(#"{"tools":[{"type":"custom","name":"exec"}]}"#.utf8), wire: .responses, adapt: true)
    }
}
