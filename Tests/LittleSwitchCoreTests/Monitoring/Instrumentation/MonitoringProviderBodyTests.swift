import AsyncHTTPClient
import Foundation
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring transparent provider body")
struct MonitoringProviderBodyTests {
    @Test("Fragmented provider streams preserve every byte and take maxima per exchange before summing")
    func fragmentedExchanges() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .messages)
        let stream = """
            data: {"message":{"usage":{"input_tokens":7,"cache_read_input_tokens":3,"cache_creation_input_tokens":2}}}

            data: {"usage":{"output_tokens":5}}

            data: {"usage":{"output_tokens":3}}

            data: [DONE]
            """
        let chunks = [Data()] + stream.utf8.map { Data([$0]) }
        let source = DemandTrackedBodySequence(chunks: chunks)
        var iterator = MonitoringProviderBody(body: .stream(source), context: context).makeAsyncIterator()
        var received: [ByteBuffer] = []
        while let buffer = try await iterator.next() { received.append(buffer) }
        let repeatedEnd = try await iterator.next()
        #expect(repeatedEnd == nil)
        #expect(received == chunks.map { ByteBuffer(bytes: $0) })
        #expect(await source.nextCallCount == chunks.count + 1)
        let second = ByteBuffer(string: #"{"usage":{"input_tokens":11,"output_tokens":4}}"#)
        var nextExchange = MonitoringProviderBody(body: .bytes(second), context: context).makeAsyncIterator()
        let forwarded = try await nextExchange.next()
        let ended = try await nextExchange.next()
        #expect(forwarded == second)
        #expect(ended == nil)
        await context.finish(statusCode: 200)
        let entries = try await store.logs().entries
        #expect(entries.count == 1)
        #expect(
            entries.first?.attributes.usage
                == .init(inputTokens: 18, outputTokens: 9, cacheReadTokens: 3, cacheWriteTokens: 2))
        #expect(await store.snapshot().family(.dropped) == nil)
    }

    @Test("Complete invalid samples and a truncated EOF are diagnosed exactly once")
    func invalidSamplesAtEOF() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        let chunks = [
            Data(#"{"usage":{"input_tokens":5}} {"usage":{"input_tokens":-1}}"#.utf8),
            Data(#"{"usage":{"output_tokens":"#.utf8),
        ]
        var iterator = MonitoringProviderBody(
            body: .stream(DemandTrackedBodySequence(chunks: chunks)), context: context
        ).makeAsyncIterator()
        while try await iterator.next() != nil {}
        let ended = try await iterator.next()
        #expect(ended == nil)
        await context.finish(statusCode: 200)
        #expect(try await store.logs().entries.first?.attributes.usage == .init(inputTokens: 5))
        #expect(
            await store.snapshot().family(.dropped)?.points == [
                .init(attributes: [.dropReason(.invalidUsage), .signal(.metrics)], value: .counter(2))
            ])
    }

    @Test("A provider failure propagates unchanged and publishes already read usage and truncation")
    func failingStream() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .messages)
        let chunk = Data(#"{"usage":{"input_tokens":5}} {"usage":{"output_tokens":"#.utf8)
        let source = DemandTrackedBodySequence(chunks: [chunk], termination: .failure)
        var iterator = MonitoringProviderBody(body: .stream(source), context: context).makeAsyncIterator()
        let forwarded = try await iterator.next()
        #expect(forwarded == ByteBuffer(bytes: chunk))
        await #expect(throws: GatewayTestError.privateFailure) { try await iterator.next() }
        let ended = try await iterator.next()
        #expect(ended == nil)
        #expect(await source.nextCallCount == 2)
        await context.finish(statusCode: 200, error: .transport)
        let entry = try #require(try await store.logs().entries.first)
        #expect(entry.attributes.usage == .init(inputTokens: 5))
        #expect(entry.attributes.outcome == .transportError)
        #expect(await store.snapshot().family(.dropped)?.points.map(\.value) == [.counter(1)])
    }

    @Test("Abandonment retains only observed usage and never drains the upstream body")
    func abandonedStream() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .messages)
        let source = DemandTrackedBodySequence(chunks: [
            Data(#"{"message":{"usage":{"input_tokens":3}}}"#.utf8),
            Data(#"{"usage":{"output_tokens":99}}"#.utf8),
        ])
        var iterator = MonitoringProviderBody(body: .stream(source), context: context).makeAsyncIterator()
        _ = try await iterator.next()
        await context.finish(error: .cancelled)
        #expect(await source.nextCallCount == 1)
        let entry = try #require(try await store.logs().entries.first)
        #expect(entry.attributes.usage == .init(inputTokens: 3))
        #expect(entry.attributes.outcome == .cancelled)
        #expect(await store.snapshot().family(.inFlight)?.points.map(\.value) == [.gauge(0)])
    }

    @Test("Cancellation stays a cancellation and an empty body leaves usage unknown")
    func cancelledEmptyStream() async throws {
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        let source = DemandTrackedBodySequence(chunks: [], termination: .cancellation)
        var iterator = MonitoringProviderBody(body: .stream(source), context: context).makeAsyncIterator()
        await #expect(throws: CancellationError.self) { try await iterator.next() }
        let ended = try await iterator.next()
        #expect(ended == nil)
        #expect(await source.nextCallCount == 1)
        await context.finish(error: .cancelled)
        #expect(try await store.logs().entries.first?.attributes.usage == nil)
        #expect(await store.snapshot().family(.tokens) == nil)
    }
}
