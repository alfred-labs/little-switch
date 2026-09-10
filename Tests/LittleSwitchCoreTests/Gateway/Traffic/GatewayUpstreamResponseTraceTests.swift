import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway ordered upstream response traces")
struct GatewayUpstreamResponseTraceTests {
    @Test("Rejected JSON retains its head and complete collected body")
    func rejectedJSON() async throws {
        let raw = Data(#"{"content":[{"type":"server_tool_use","name":"unowned"}]}"#.utf8)
        let recorder = TrafficTestRecorder()
        let responder = try makeResponder(body: raw, recorder: recorder)
        await #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            _ = try await exchange(responder)
        }
        let recorded = try #require(recorder.events.first?.upstreamExchanges.first)
        #expect(recorded.responseStatus == 200)
        #expect(recorded.response.body == raw)
    }

    @Test("JSON collection failures preserve the prefix already received")
    func interruptedJSON() async throws {
        let raw = Data(#"{"content":["#.utf8)
        let recorder = TrafficTestRecorder()
        let responder = try makeResponder(body: raw, recorder: recorder, failsAfterBody: true)
        await #expect(throws: GatewayTestError.failure) {
            _ = try await exchange(responder)
        }
        #expect(recorder.events.first?.upstreamExchanges.first?.response.body == raw)
    }

    @Test("Successful JSON is recorded before publication and is not duplicated by its consumer")
    func successfulJSON() async throws {
        let raw = Data(#"{"content":[{"type":"text","text":"hello"}]}"#.utf8)
        let recorder = TrafficTestRecorder()
        let responder = try makeResponder(body: raw, recorder: recorder)
        let model = try await exchange(responder)
        #expect(recorder.events.first?.upstreamExchanges.first?.response.body == raw)
        let response = responder.streamingResponse(model.response, eventID: eventID, attempt: 3, trace: model.trace)
        #expect(try await responseBodyData(response.body) == raw)
        #expect(recorder.events.first?.upstreamExchanges.first?.response.body == raw)
    }

    @Test("Fragmented SSE records accepted and rejected bytes in their original order")
    func fragmentedSSERejection() async throws {
        let good = Data("data: {\"type\":\"ping\"}\n\n".utf8)
        let bad = Data("data: {\"content_block\":{\"type\":\"server_tool_use\",\"name\":\"unowned\"}}\n\n".utf8)
        let raw = good + bad
        let recorder = TrafficTestRecorder()
        let responder = try makeResponder(body: raw, recorder: recorder, streaming: true, bytewise: true)
        let model = try await exchange(responder)
        let response = responder.streamingResponse(
            model.response, eventID: eventID, attempt: 3, errorStyle: .anthropic, trace: model.trace)
        let recordedResponse = responder.recordingClientResponse(response, eventID: eventID)
        let output = try await responseBodyData(recordedResponse.body)
        #expect(output.starts(with: good))
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(!text.contains("unowned"))
        model.trace.finish()
        #expect(recorder.events.first?.upstreamExchanges.first?.response.body == raw)
        #expect(recorder.events.first?.lifecycle == .failed)
    }

    @Test("A buffered consumer traces accepted SSE bytes even when collection later fails")
    func collectionFailure() async throws {
        let good = Data("data: {\"type\":\"ping\"}\n\n".utf8)
        let bad = Data("data: {\"content_block\":{\"type\":\"server_tool_use\"}}\n\n".utf8)
        let recorder = TrafficTestRecorder()
        let responder = try makeResponder(body: good + bad, recorder: recorder, streaming: true, bytewise: true)
        let model = try await exchange(responder)
        await #expect(throws: ProviderToolContract.Error.providerOwnedTool) {
            _ = try await model.trace.collect(model.response.body, upTo: 1_024)
        }
        #expect(recorder.events.first?.upstreamExchanges.first?.response.body == good + bad)
    }

    @Test("Writer failure and cancellation flush exactly the accepted prefix")
    func writerFailures() async throws {
        let good = Data("data: {\"type\":\"ping\"}\n\n".utf8)
        let unread = Data("data: {\"content_block\":{\"type\":\"server_tool_use\"}}\n\n".utf8)
        for failure in [CoverageWriterFailure.error, .cancellation] {
            let recorder = TrafficTestRecorder()
            let responder = try makeResponder(body: good + unread, recorder: recorder, streaming: true, bytewise: true)
            let model = try await exchange(responder)
            let response = responder.streamingResponse(
                model.response, eventID: eventID, attempt: 3, errorStyle: .anthropic, trace: model.trace)
            if failure == .cancellation {
                await #expect(throws: CancellationError.self) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            } else {
                await #expect(throws: GatewayTestError.privateFailure) {
                    try await response.body.write(CoverageThrowingWriter(failure: failure))
                }
            }
            model.trace.finish()
            model.trace.append(Data("stale".utf8))
            #expect(recorder.events.first?.upstreamExchanges.first?.response.body == good)
        }
    }

    @Test("SSE that can emit a gateway error excludes provider representation headers")
    func rewrittenSSEHeaders() throws {
        let raw = Data("data: {\"type\":\"ping\"}\n\n".utf8)
        let responder = try makeResponder(body: raw, recorder: TrafficTestRecorder())
        let upstream = HTTPClientResponse(
            headers: [
                "content-type": "text/event-stream", "content-length": "200", "etag": "provider", "digest": "hash",
            ],
            body: .bytes(ByteBuffer(bytes: raw))
        )
        let response = responder.streamingResponse(upstream, eventID: eventID, attempt: 0, errorStyle: .openAI)
        #expect(response.headers[.contentLength] == nil)
        #expect(response.headers[.eTag] == nil)
        #expect(response.headers[try #require(HTTPField.Name("digest"))] == nil)
    }

    private let eventID = UUID()

    private func exchange(_ responder: GatewayResponder) async throws -> GatewayModelExchange {
        try await responder.executeModelRequest(
            HTTPClientRequest(url: "https://provider.invalid/v1/messages"),
            body: Data("{}".utf8),
            wire: .anthropic,
            eventID: eventID,
            attempt: 3)
    }

    private func makeResponder(
        body: Data,
        recorder: TrafficTestRecorder,
        streaming: Bool = false,
        bytewise: Bool = false,
        failsAfterBody: Bool = false
    ) throws -> GatewayResponder {
        let fixture = try GatewayTests().makeFixture()
        let chunks = bytewise ? body.map { ByteBuffer(bytes: [$0]) } : [ByteBuffer(bytes: body)]
        let response = HTTPClientResponse(
            headers: ["content-type": streaming ? "text/event-stream" : "application/json"],
            body: .stream(TraceTestChunks(chunks: chunks, failsAfterBody: failsAfterBody))
        )
        return GatewayResponder(
            state: fixture.state,
            transport: RecordingGatewayTransport(responses: [response]),
            secretStore: fixture.secrets,
            requiredAuthorityPort: nil,
            trafficRecorder: recorder
        )
    }
}

private struct TraceTestChunks: AsyncSequence, Sendable {
    let chunks: [ByteBuffer]
    let failsAfterBody: Bool

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(chunks: chunks.makeIterator(), failsAfterBody: failsAfterBody)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var chunks: IndexingIterator<[ByteBuffer]>
        let failsAfterBody: Bool

        mutating func next() async throws -> ByteBuffer? {
            if let chunk = chunks.next() { return chunk }
            if failsAfterBody { throw GatewayTestError.failure }
            return nil
        }
    }
}
