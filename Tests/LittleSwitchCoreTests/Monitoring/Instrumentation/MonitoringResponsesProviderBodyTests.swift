import AsyncHTTPClient
import Foundation
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring Responses provider body")
struct MonitoringResponsesProviderBodyTests {
    @Test(
        "A single steered body accounts for both responses without changing forwarded bytes", arguments: [false, true])
    func successorUsage(fragmented: Bool) async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        let stream = """
            data: {"response":{"id":"resp_1","usage":{"input_tokens":10,"output_tokens":3}}}

            data: {"response":{"id":"resp_2","usage":{"input_tokens":12,"output_tokens":4}}}

            data: {"response":{"id":"resp_2","usage":{"input_tokens":12,"output_tokens":4}}}
            """
        let chunks = fragmented ? stream.utf8.map { Data([$0]) } : [Data(stream.utf8)]
        let source = DemandTrackedBodySequence(chunks: chunks)
        var iterator = MonitoringProviderBody(body: .stream(source), context: context).makeAsyncIterator()
        var forwarded: [ByteBuffer] = []
        while let buffer = try await iterator.next() { forwarded.append(buffer) }
        await context.finish(statusCode: 200)
        #expect(forwarded == chunks.map { ByteBuffer(bytes: $0) })
        #expect(await source.nextCallCount == chunks.count + 1)
        #expect(try await store.logs().entries.first?.attributes.usage == .init(inputTokens: 22, outputTokens: 7))
        #expect(await store.snapshot().family(.dropped) == nil)
    }

    @Test("Oversized response identities are diagnosed once without consuming private content")
    func oversizedIdentity() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        let body =
            "{\"response\":{\"id\":\"\(String(repeating: "x", count: 256))\",\"usage\":{\"input_tokens\":3}}}"
        var iterator = MonitoringProviderBody(
            body: .bytes(ByteBuffer(string: body)), context: context
        ).makeAsyncIterator()
        while try await iterator.next() != nil {}
        await context.oversizedUsage(count: 0)
        await context.oversizedUsage(count: -1)
        await context.finish(statusCode: 200)
        await context.oversizedUsage(count: 99)
        #expect(try await store.logs().entries.first?.attributes.usage == nil)
        #expect(
            await store.snapshot().family(.dropped)?.points == [
                .init(attributes: [.dropReason(.oversize), .signal(.metrics)], value: .counter(1))
            ])
    }

    @Test("Abandoning a response retains complete observed usage without draining its remaining output")
    func abandonedResponse() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        let source = DemandTrackedBodySequence(chunks: [
            Data(#"{"response":{"id":"resp_1","usage":{"input_tokens":3},"output":["#.utf8),
            Data(#"]}}"#.utf8),
        ])
        var iterator = MonitoringProviderBody(body: .stream(source), context: context).makeAsyncIterator()
        _ = try await iterator.next()
        await context.finish(error: .cancelled)
        #expect(await source.nextCallCount == 1)
        #expect(try await store.logs().entries.first?.attributes.usage == .init(inputTokens: 3))
    }
}
