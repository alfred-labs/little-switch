import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool transport cancellation and errors")
struct ProviderToolContractTransportEdgeTests {
    @Test("Cancellation is observed before buffering and before pulling stream bytes")
    func cancellation() async throws {
        let initial = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await ProviderToolResponse.validated(
                HTTPClientResponse(body: .bytes(ByteBuffer(string: "{}"))),
                requestBody: Data("{}".utf8),
                wire: .anthropic,
                maximumBytes: 128
            )
        }
        await #expect(throws: CancellationError.self) { try await initial.value }

        let response = try await validatedStream("data: {}\n\n")
        let streaming = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = response.body.makeAsyncIterator()
            _ = try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await streaming.value }
    }

    @Test("Underlying transport errors remain errors for both response modes")
    func upstreamFailure() async throws {
        await #expect(throws: GatewayTestError.failure) {
            _ = try await ProviderToolResponse.validated(
                failingResponse(error: GatewayTestError.failure),
                requestBody: jsonData([:]),
                wire: .anthropic,
                maximumBytes: 128
            )
        }
        var upstream = failingResponse(error: GatewayTestError.failure)
        upstream.headers.add(name: "content-type", value: "text/event-stream")
        let stream = try await ProviderToolResponse.validated(
            upstream, requestBody: jsonData([:]), wire: .anthropic, maximumBytes: 128)
        await #expect(throws: GatewayTestError.failure) { _ = try await stream.body.collect(upTo: 128) }
    }

    @Test("A complete frame group is checked before any byte from that group is yielded")
    func rejectedFrameGroup() async throws {
        let good = "data: {\"type\":\"message_start\",\"message\":{\"content\":[]}}\n\n"
        let bad = "data: {\"type\":\"content_block_start\",\"content_block\":{\"type\":\"server_tool_use\"}}\n\n"
        let response = try await validatedStream(good + bad)
        var iterator = response.body.makeAsyncIterator()
        await #expect(throws: ProviderToolContract.Error.providerOwnedTool) { _ = try await iterator.next() }
        #expect(try await iterator.next() == nil)
    }

    @Test("Malformed residual SSE is rejected and deferred valid frames keep exact bytes")
    func residualFrames() async throws {
        let incomplete = try await validatedStream("data: {}")
        await #expect(throws: ServerSentEventDecoder.Error.incompleteFrame) {
            _ = try await incomplete.body.collect(upTo: 128)
        }
        let raw = "data: {}\r\r"
        let deferred = try await validatedStream(raw)
        let body = try await deferred.body.collect(upTo: 128)
        #expect(Data(body.readableBytesView) == Data(raw.utf8))
        let empty = try await validatedStream("")
        #expect(try await empty.body.collect(upTo: 128).readableBytes == 0)
    }

    @Test("Invalid size bounds fail explicitly")
    func invalidBounds() async throws {
        for maximum in [0, -1, Int.max] {
            await #expect(throws: ProviderToolContract.Error.invalidResponse) {
                _ = try await ProviderToolResponse.validated(
                    HTTPClientResponse(body: .bytes(ByteBuffer(string: "{}"))),
                    requestBody: jsonData([:]),
                    wire: .anthropic,
                    maximumBytes: maximum
                )
            }
        }
    }

    private func validatedStream(_ raw: String) async throws -> HTTPClientResponse {
        try await ProviderToolResponse.validated(
            HTTPClientResponse(headers: ["content-type": "text/event-stream"], body: .bytes(ByteBuffer(string: raw))),
            requestBody: jsonData([:]),
            wire: .anthropic,
            maximumBytes: 1_024
        )
    }
}
