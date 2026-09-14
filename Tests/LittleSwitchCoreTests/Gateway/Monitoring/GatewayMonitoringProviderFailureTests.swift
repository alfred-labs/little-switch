import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LittleSwitchCommon
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Gateway monitoring provider failures")
struct GatewayMonitoringProviderFailureTests {
    @Test(
        "Native provider failures preserve the HTTP 200 wire, usage and exactly one failed observation",
        arguments: [MonitoringRoute.messages, .responses], [1, 4_096])
    func nativeFailure(route: MonitoringRoute, chunkSize: Int) async throws {
        let fixture = try GatewayTests().makeFixture()
        let provider = try #require(fixture.snapshot.providers.first)
        await fixture.state.responsesCapabilities.record(providerID: provider.id, supportsNative: true)
        let store = MonitoringStore()
        let stream = Self.stream(for: route)
        let bytes = Data(stream.utf8)
        let chunks = stride(from: 0, to: bytes.count, by: chunkSize).map {
            Data(bytes.dropFirst($0).prefix(chunkSize))
        }
        let transport = RecordingGatewayTransport(responses: [
            HTTPClientResponse(
                status: .ok,
                headers: ["content-type": "text/event-stream"],
                body: .stream(DemandTrackedBodySequence(chunks: chunks)))
        ])
        let monitoring = GatewayMonitoring(store: store) { .init(exposeLogs: true) }
        let app = Application(
            responder: GatewayResponder(
                state: fixture.state,
                transport: transport,
                secretStore: fixture.secrets,
                requiredAuthorityPort: nil,
                monitoring: monitoring))
        let mapping = try #require(fixture.snapshot.codex.resolvedDefaultModel(in: fixture.snapshot.providers))
        let model =
            route == .messages ? "claude-opus-5" : CodexCatalog.slug(for: mapping, in: fixture.snapshot.providers)
        let body: [String: Any] =
            route == .messages
            ? ["model": model, "stream": true, "messages": [["role": "user", "content": "Synthetic request"]]]
            : ["model": model, "stream": true, "input": "Synthetic request"]
        let requestBody = ByteBuffer(bytes: try JSONSerialization.data(withJSONObject: body))
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: route == .messages ? "/v1/messages" : "/v1/responses",
                method: .post,
                headers: [.contentType: "application/json"],
                body: requestBody)
            #expect(response.status == .ok)
            #expect(Data(response.body.readableBytesView) == bytes)
        }
        let entries = try await store.logs().entries
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.attributes.outcome == .serverError)
        #expect(entry.attributes.statusCode == 200)
        #expect(entry.attributes.errorKind?.rawValue == "provider_response")
        #expect(entry.attributes.usage == .init(inputTokens: 7, outputTokens: 3))
        #expect(entry.level == .error)
        #expect(entry.eventName == "gateway.request.failed")
        let snapshot = await store.snapshot()
        #expect(snapshot.family(.requests)?.points.map(\.value) == [.counter(1)])
        #expect(snapshot.family(.requests)?.points.first?.attributes.contains(.outcome(.serverError)) == true)
        #expect(snapshot.family(.inFlight)?.points.map(\.value) == [.gauge(0)])
        let exported = try OTLPLogsEncoder.encode(resource: store.resource, entries: entries)
        let exportedText = try #require(String(bytes: exported, encoding: .utf8))
        let exportsPrivateError = exportedText.contains("PRIVATE_ERROR")
        #expect(!exportsPrivateError)
        #expect(await transport.requests.count == 1)
    }

    @Test("The response observer ignores unrelated and malformed frames without changing the bytes")
    func unrelatedFrames() async throws {
        let stream = """
            : event: error
            event: message
            data: {"type":"message","content":[{"type":"error","error":{}}]}

            event: error
            data: {"type":"message","error":{}}

            event: error
            data: {"type":"error","error":"PRIVATE_ERROR"}

            event: response.failed
            data: {"type":"response.failed","response":{"status":"completed"}}

            data: {"type":"error","error":}

            data: [DONE]


            """
        let entry = try await observe(stream)
        #expect(entry.attributes.outcome == .success)
        #expect(entry.attributes.errorKind == nil)
    }

    @Test("An oversized frame is skipped and a fragmented later failure is still observed")
    func boundedFrameRecovery() async throws {
        let oversized =
            "data: {\"type\":\"message\",\"text\":\"" + String(repeating: "x", count: 100_000) + "\"}\r\n\r\n"
        let failure = "event: error\r\ndata: {\"type\":\"error\",\"error\":{\"message\":\"PRIVATE_ERROR\"}}\r\n\r\n"
        let entry = try await observe(oversized + failure + failure, chunkSize: 127)
        #expect(entry.attributes.outcome == .serverError)
        #expect(entry.attributes.errorKind?.rawValue == "provider_response")
    }

    @Test("Explicit SSE failure events remain failures when their remote payload exceeds the observation buffer")
    func oversizedFailures() async throws {
        let large = String(repeating: "PRIVATE_ERROR", count: 10_000)
        let streams = [
            "event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"\(large)\"}}\n\n",
            "event: response.failed\ndata: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\","
                + "\"output\":[{\"content\":\"\(large)\"}]}}\n\n",
        ]
        for stream in streams {
            let entry = try await observe(stream, chunkSize: 127)
            #expect(entry.attributes.outcome == .serverError)
            #expect(entry.attributes.errorKind == .providerResponse)
            #expect(entry.level == .error)
        }
    }

    @Test("Non-SSE bodies cannot impersonate an in-band provider failure")
    func contentTypeBoundary() async throws {
        let entry = try await observe(Self.failure, contentType: "application/json")
        #expect(entry.attributes.outcome == .success)
        #expect(entry.attributes.errorKind == nil)
    }

    @Test(
        "HTTP errors keep their existing classification when an SSE body also signals failure",
        arguments: [HTTPResponse.Status.badRequest, .badGateway])
    func httpFailurePrecedence(status: HTTPResponse.Status) async throws {
        let entry = try await observe(Self.failure, status: status)
        #expect(entry.attributes.statusCode == status.code)
        #expect(entry.attributes.outcome == (status == .badRequest ? .clientError : .serverError))
        #expect(entry.attributes.errorKind == (status == .badRequest ? .invalidRequest : .providerHTTP))
        #expect(entry.level == (status == .badRequest ? .warn : .error))
    }

    @Test("Cancellation and transport failures take precedence over an observed provider failure")
    func terminalPrecedence() async throws {
        for cancelled in [false, true] {
            let entry = try await observe(Self.failure, ending: cancelled ? .cancelled : .transport)
            #expect(entry.attributes.outcome == (cancelled ? .cancelled : .transportError))
            #expect(entry.attributes.errorKind == (cancelled ? .cancelled : .transport))
        }
    }

    private static let failure =
        "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"PRIVATE_ERROR\"}}\n\n"

    private static func stream(for route: MonitoringRoute) -> String {
        if route == .messages {
            return "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"content\":[],"
                + "\"usage\":{\"input_tokens\":7,\"output_tokens\":3}}}\n\n" + failure
        }
        return "event: response.failed\ndata: {\"type\":\"response.failed\",\"response\":{\"id\":\"synthetic\","
            + "\"object\":\"response\",\"status\":\"failed\",\"output\":[],"
            + "\"usage\":{\"input_tokens\":7,\"output_tokens\":3},"
            + "\"error\":{\"code\":\"server_error\",\"message\":\"PRIVATE_ERROR\"}}}\n\n"
    }

    private func observe(
        _ stream: String,
        chunkSize: Int = 11,
        contentType: String = "text/event-stream",
        status: HTTPResponse.Status = .ok,
        ending: MonitoringErrorKind? = nil
    ) async throws -> MonitoringLogEntry {
        let fixture = try GatewayTests().makeFixture()
        let store = MonitoringStore()
        let context = await GatewayMonitoring(store: store).begin(requestID: UUID(), route: .responses)
        let responder = GatewayResponder(
            state: fixture.state, transport: RecordingGatewayTransport(responses: []), secretStore: fixture.secrets)
        let bytes = Data(stream.utf8)
        let source = Response(
            status: status,
            headers: [.contentType: contentType],
            body: .init { writer in
                for offset in stride(from: 0, to: bytes.count, by: chunkSize) {
                    try await writer.write(.init(bytes: bytes.dropFirst(offset).prefix(chunkSize)))
                }
                if ending == .cancelled { throw CancellationError() }
                if ending == .transport { throw GatewayTestError.privateFailure }
                try await writer.finish(nil)
            })
        let response = GatewayMonitoringScope.$current.withValue(context) {
            responder.recordingClientResponse(source, eventID: UUID())
        }
        if ending == nil {
            #expect(try await responseBodyData(response.body) == bytes)
        } else {
            await #expect(throws: (any Error).self) { try await responseBodyData(response.body) }
        }
        await context.finish(statusCode: status.code)
        await context.providerResponseFailed()
        let entries = try await store.logs().entries
        #expect(entries.count == 1)
        #expect(await store.snapshot().family(.inFlight)?.points.map(\.value) == [.gauge(0)])
        let entry = try #require(entries.first)
        let encodedEntry = try JSONEncoder().encode(entry)
        let entryText = try #require(String(bytes: encodedEntry, encoding: .utf8))
        let retainsPrivateError = entryText.contains("PRIVATE_ERROR")
        #expect(!retainsPrivateError)
        return entry
    }
}
