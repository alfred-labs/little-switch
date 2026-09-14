import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool contract transport boundary")
struct ProviderToolContractTransportTests {
    @Test("Buffered JSON is validated before returning and preserves every byte")
    func bufferedJSON() async throws {
        let payload = try jsonData(["content": [["type": "text", "text": "ordinary"]]])
        let original = response(payload)
        let validated = try await ProviderToolResponse.validated(
            original, requestBody: jsonData([:]), wire: .anthropic, maximumBytes: 1_024)
        #expect(validated.status == original.status)
        #expect(validated.headers == original.headers)
        #expect(try await collect(validated) == payload)
        let rejected = response(try jsonData(["content": [["type": "server_tool_use", "name": "analyze_image"]]]))
        await #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            _ = try await ProviderToolResponse.validated(
                rejected, requestBody: jsonData([:]), wire: .anthropic, maximumBytes: 1_024)
        }
    }

    @Test("HTTP errors pass through without parsing body or request")
    func httpErrors() async throws {
        let body = Data("provider private failure".utf8)
        let original = HTTPClientResponse(
            status: .badRequest, headers: ["x-test": "same"], body: .bytes(ByteBuffer(bytes: body)))
        let validated = try await ProviderToolResponse.validated(
            original, requestBody: Data(), wire: .anthropic, maximumBytes: 1)
        #expect(validated.status == .badRequest)
        #expect(validated.headers == original.headers)
        #expect(try await collect(validated) == body)
    }

    @Test("SSE validates byte fragments while retaining comments, IDs, separators, and whitespace")
    func exactSSEBytes() async throws {
        let raw = Data(
            (": hello\r\nid: 7\r\nevent: content_block_start\r\n"
                + "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"ok\"}}\r\n\r\n"
                + "retry: 100\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n \n").utf8)
        let original = response(raw, sse: true, bytewise: true)
        let validated = try await ProviderToolResponse.validated(
            original, requestBody: jsonData([:]), wire: .anthropic, maximumBytes: 1_024)
        #expect(try await collect(validated) == raw)
    }

    @Test("A rejected server-tool frame is never yielded, even when received byte by byte")
    func noRejectedFrameBytes() async throws {
        let good = Data("data: {\"type\":\"message_start\",\"message\":{\"content\":[]}}\n\n".utf8)
        let bad = Data(
            "data: {\"type\":\"content_block_start\",\"content_block\":{\"type\":\"server_tool_use\",\"name\":\"private\"}}\n\n"
                .utf8)
        let validated = try await ProviderToolResponse.validated(
            response(good + bad, sse: true, bytewise: true),
            requestBody: jsonData([:]),
            wire: .anthropic,
            maximumBytes: 1_024
        )
        var iterator = validated.body.makeAsyncIterator()
        var emitted = Data()
        do {
            while let chunk = try await iterator.next() { emitted.append(contentsOf: chunk.readableBytesView) }
            Issue.record("Expected the provider-owned frame to fail")
        } catch {
            #expect(error as? ProviderToolContract.Error == .providerOwnedTool)
        }
        #expect(emitted == good)
        #expect(try await iterator.next() == nil)
    }

    @Test("An incomplete tool name fails at EOF without a stale successful finish")
    func unfinishedName() async throws {
        let raw = Data(
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"rea\"}}]}}]}\r\r"
                .utf8)
        let request = try jsonData(["tools": [["type": "function", "function": ["name": "read"]]]])
        let validated = try await ProviderToolResponse.validated(
            response(raw, sse: true), requestBody: request, wire: .chatCompletions, maximumBytes: 1_024)
        var iterator = validated.body.makeAsyncIterator()
        await #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "rea")) {
            _ = try await iterator.next()
        }
        #expect(try await iterator.next() == nil)
    }

    @Test("Large JSON and individual SSE frames are bounded")
    func boundedBodies() async throws {
        let payload = try jsonData(["content": [["type": "text", "text": String(repeating: "x", count: 200)]]])
        await #expect(throws: NIOTooManyBytesError.self) {
            _ = try await ProviderToolResponse.validated(
                response(payload), requestBody: jsonData([:]), wire: .anthropic, maximumBytes: 32)
        }
        let validated = try await ProviderToolResponse.validated(
            response(Data("data: ".utf8) + payload + Data("\n\n".utf8), sse: true),
            requestBody: jsonData([:]),
            wire: .anthropic,
            maximumBytes: 32
        )
        await #expect(throws: ServerSentEventDecoder.Error.frameTooLarge) { _ = try await collect(validated) }
    }

    @Test("A large chunk containing many bounded frames does not become a total-stream limit")
    func manyFramesInOneChunk() async throws {
        let raw = Data(String(repeating: ": keepalive\n\n", count: 100).utf8)
        let validated = try await ProviderToolResponse.validated(
            response(raw, sse: true), requestBody: jsonData([:]), wire: .anthropic, maximumBytes: 24)
        #expect(try await collect(validated) == raw)
    }

    @Test("Decoder byte accounting includes ignored frames and deferred final delimiters")
    func decoderConsumedBytes() throws {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 128)
        let comment = ByteBuffer(string: ": comment\n\n")
        #expect(try decoder.append(comment).isEmpty)
        #expect(decoder.consumedBytes == comment.readableBytes)
        let frame = ByteBuffer(string: "data: {}\r\r")
        #expect(try decoder.append(frame).isEmpty)
        #expect(decoder.consumedBytes == comment.readableBytes)
        #expect(try decoder.finish().count == 1)
        #expect(decoder.consumedBytes == comment.readableBytes + frame.readableBytes)
        #expect(try decoder.finish().isEmpty)
    }

    private func response(_ body: Data, sse: Bool = false, bytewise: Bool = false) -> HTTPClientResponse {
        let chunks = bytewise ? body.map { ByteBuffer(bytes: [$0]) } : [ByteBuffer(bytes: body)]
        return HTTPClientResponse(
            headers: ["content-type": sse ? "Text/Event-Stream; charset=utf-8" : "application/json"],
            body: .stream(ProviderContractChunks(chunks: chunks))
        )
    }

    private func collect(_ response: HTTPClientResponse) async throws -> Data {
        let buffer = try await response.body.collect(upTo: 16_384)
        return Data(buffer.readableBytesView)
    }
}

private struct ProviderContractChunks: AsyncSequence, Sendable {
    let chunks: [ByteBuffer]

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(chunks: chunks.makeIterator()) }

    struct AsyncIterator: AsyncIteratorProtocol {
        var chunks: IndexingIterator<[ByteBuffer]>

        mutating func next() async throws -> ByteBuffer? { chunks.next() }
    }
}
