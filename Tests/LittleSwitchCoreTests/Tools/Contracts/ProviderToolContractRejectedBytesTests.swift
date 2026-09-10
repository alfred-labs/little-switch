import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Provider tool rejection byte accounting")
struct ProviderToolContractRejectedBytesTests {
    @Test("A rejected collected JSON body is reported exactly once")
    func rejectedJSON() async throws {
        let raw = try jsonData(["content": [["type": "server_tool_use", "name": "unowned"]]])
        _ = await confirmation("rejected bytes", expectedCount: 1) { reported in
            await #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
                _ = try await ProviderToolResponse.validated(
                    HTTPClientResponse(body: .bytes(ByteBuffer(bytes: raw))),
                    requestBody: Data("{}".utf8),
                    wire: .anthropic,
                    maximumBytes: 1_024
                ) { bytes in
                    #expect(bytes == raw)
                    reported()
                }
            }
        }
    }

    @Test("Rejected SSE bytes exclude prior yielded chunks and cannot be reported again")
    func rejectedSSE() async throws {
        let good = Data("data: {\"type\":\"message_start\",\"message\":{\"content\":[]}}\n\n".utf8)
        let bad = Data(
            "data: {\"type\":\"content_block_start\",\"content_block\":{\"type\":\"server_tool_use\"}}\n\n".utf8)
        try await confirmation("rejected bytes", expectedCount: 1) { reported in
            let response = try await ProviderToolResponse.validated(
                stream([good, bad]),
                requestBody: Data("{}".utf8),
                wire: .anthropic,
                maximumBytes: 1_024
            ) { bytes in
                #expect(bytes == bad)
                reported()
            }
            var iterator = response.body.makeAsyncIterator()
            let accepted = try #require(try await iterator.next())
            #expect(Data(accepted.readableBytesView) == good)
            await #expect(throws: ProviderToolContract.Error.providerOwnedTool) { _ = try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
    }

    @Test("A rejected oversized SSE reports only the bounded prefix retained so far")
    func rejectedPrefixIsBounded() async throws {
        let raw = Data(("data: " + String(repeating: "x", count: 500)).utf8)
        try await confirmation("rejected prefix", expectedCount: 1) { reported in
            let response = try await ProviderToolResponse.validated(
                stream([raw]),
                requestBody: Data("{}".utf8),
                wire: .anthropic,
                maximumBytes: 32
            ) { bytes in
                #expect(bytes == raw.prefix(36))
                reported()
            }
            await #expect(throws: ServerSentEventDecoder.Error.frameTooLarge) {
                _ = try await response.body.collect(upTo: 1_024)
            }
        }
    }

    @Test("Successful responses and untouched HTTP errors do not report rejected bytes")
    func successfulAndHTTPErrorBytes() async throws {
        let ordinary = Data("{\"content\":[]}".utf8)
        let responses = [
            HTTPClientResponse(body: .bytes(ByteBuffer(bytes: ordinary))),
            stream([Data("data: {\"type\":\"message_stop\"}\n\n".utf8)]),
            HTTPClientResponse(status: .badRequest, body: .bytes(ByteBuffer(string: "provider error"))),
        ]
        for response in responses {
            let validated = try await ProviderToolResponse.validated(
                response,
                requestBody: Data("{}".utf8),
                wire: .anthropic,
                maximumBytes: 1_024
            ) { _ in Issue.record("Unexpected rejected bytes") }
            #expect(try await validated.body.collect(upTo: 1_024).readableBytes > 0)
        }
    }

    @Test("Empty transport chunks do not stall a stream or revive it after EOF")
    func emptyChunksAndEOF() async throws {
        let raw = Data("data: {\"type\":\"message_stop\"}\n\n".utf8)
        let validated = try await ProviderToolResponse.validated(
            stream([Data(), Data(raw.prefix(3)), Data(), Data(raw.dropFirst(3)), Data()]),
            requestBody: Data("{}".utf8),
            wire: .anthropic,
            maximumBytes: 1_024
        ) { _ in Issue.record("Successful stream reported rejected bytes") }
        var iterator = validated.body.makeAsyncIterator()
        let output = try #require(try await iterator.next())
        #expect(Data(output.readableBytesView) == raw)
        #expect(try await iterator.next() == nil)
        #expect(try await iterator.next() == nil)
    }

    private func stream(_ chunks: [Data]) -> HTTPClientResponse {
        HTTPClientResponse(
            headers: ["content-type": "text/event-stream"],
            body: .stream(RejectedByteChunks(chunks: chunks.map { ByteBuffer(bytes: $0) }))
        )
    }
}

private struct RejectedByteChunks: AsyncSequence, Sendable {
    let chunks: [ByteBuffer]

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(chunks: chunks.makeIterator()) }

    struct AsyncIterator: AsyncIteratorProtocol {
        var chunks: IndexingIterator<[ByteBuffer]>

        mutating func next() async throws -> ByteBuffer? { chunks.next() }
    }
}
