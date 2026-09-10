import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchCore

@Suite("Provider namespace probe")
struct ProviderNamespaceProberTests {
    private static func probeProvider() -> Provider {
        Provider(
            name: "Probe",
            baseURL: "https://example.com/api",
            authMode: .bearer
        )
    }

    /// One FIFO answer with the given status and body: the namespace probe
    /// issues exactly one request per run.
    private static func transport(status: UInt, body: String) -> RecordingGatewayTransport {
        let response = HTTPClientResponse(
            status: HTTPResponseStatus(statusCode: Int(status)),
            headers: ["content-type": "application/json"],
            body: .bytes(ByteBuffer(string: body))
        )
        return RecordingGatewayTransport(responses: [response])
    }

    private static func restoredBody() -> String {
        #"{"output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"ping","namespace":"ls_probe","arguments":"{}"}],"status":"completed"}"#
    }

    @Test("A native pair answer is restored evidence")
    func nativePairIsRestored() async throws {
        let transport = Self.transport(status: 200, body: Self.restoredBody())
        let prober = ProviderNamespaceProber(transport: transport)

        let probe = try await prober.probe(
            provider: Self.probeProvider(), secret: "selected-secret", model: "probe-model"
        )

        #expect(probe.verdict == .restored)
        #expect(probe.model == "probe-model")

        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url.hasSuffix("/v1/responses"))
        #expect(request.headers["authorization"] == ["Bearer selected-secret"])
        let object = try #require(
            try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        #expect(object["model"] as? String == "probe-model")
        #expect(object["stream"] as? Bool == false)
        #expect(object["max_output_tokens"] as? Int == 16)
        let tools = try #require(object["tools"] as? [[String: Any]])
        let namespace = try #require(tools.first { $0["type"] as? String == "namespace" })
        #expect(namespace["name"] as? String == "ls_probe")
        let choice = try #require(object["tool_choice"] as? [String: Any])
        #expect(choice["type"] as? String == "function")
        #expect(choice["name"] as? String == "ping")
        #expect(choice["namespace"] as? String == "ls_probe")
    }

    @Test(
        "Any spelling the gateway can resolve is restored evidence",
        arguments: [
            #"{"output":[{"type":"function_call","name":"ping","arguments":"{}"}]}"#,
            #"{"output":[{"type":"function_call","name":"ls_probe__ping","arguments":"{}"}]}"#,
        ])
    func resolvableSpellingsAreRestored(body: String) async throws {
        let prober = ProviderNamespaceProber(transport: Self.transport(status: 200, body: body))

        let probe = try await prober.probe(
            provider: Self.probeProvider(), secret: nil, model: "m"
        )

        #expect(probe.verdict == .restored)
    }

    @Test("A 2xx that never calls the probe tool is a silent drop")
    func silentDrop() async throws {
        let prober = ProviderNamespaceProber(
            transport: Self.transport(
                status: 200,
                body: #"{"output":[{"type":"message","role":"assistant","content":[]}],"status":"completed"}"#
            )
        )

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == .silentlyDropped)
    }

    @Test(
        "A foreign namespace in the answer is not the probe tool calling",
        arguments: [
            #"{"output":[{"type":"function_call","name":"ping","namespace":"elsewhere","arguments":"{}"}]}"#
        ])
    func foreignNamespaceIsNotRestored(body: String) async throws {
        let prober = ProviderNamespaceProber(transport: Self.transport(status: 200, body: body))

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == .silentlyDropped)
    }

    @Test("An unrelated tool call is not the probe tool calling")
    func unrelatedToolCallIsNotRestored() async throws {
        let prober = ProviderNamespaceProber(
            transport: Self.transport(
                status: 200,
                body: #"{"output":[{"type":"function_call","name":"other_tool","arguments":"{}"}]}"#
            )
        )

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == .silentlyDropped)
    }

    @Test(
        "Shape rejections are rejected; auth, quota, proxy, timeout, and servers stay unknown",
        arguments: [
            (UInt(400), ProviderNamespaceVerdict.rejected),
            (UInt(404), ProviderNamespaceVerdict.rejected),
            (UInt(422), ProviderNamespaceVerdict.rejected),
            (UInt(401), ProviderNamespaceVerdict.unknown),
            (UInt(402), ProviderNamespaceVerdict.unknown),
            (UInt(403), ProviderNamespaceVerdict.unknown),
            (UInt(407), ProviderNamespaceVerdict.unknown),
            (UInt(408), ProviderNamespaceVerdict.unknown),
            (UInt(429), ProviderNamespaceVerdict.unknown),
            (UInt(500), ProviderNamespaceVerdict.unknown),
            (UInt(503), ProviderNamespaceVerdict.unknown),
        ])
    func statusClassification(status: UInt, expected: ProviderNamespaceVerdict) async throws {
        let prober = ProviderNamespaceProber(
            transport: Self.transport(
                status: status, body: #"{"detail":"x"}"#
            )
        )

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == expected)
    }

    @Test("An unreadable 2xx body stays unknown instead of pretending a silent drop")
    func unreadableBodyStaysUnknown() async throws {
        let prober = ProviderNamespaceProber(
            transport: Self.transport(status: 200, body: "<html>not json</html>")
        )

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == .unknown)
    }

    @Test("A 2xx whose body cannot be collected stays unknown")
    func failingBodyStaysUnknown() async throws {
        let stream = AsyncThrowingStream<ByteBuffer, any Swift.Error> { continuation in
            continuation.finish(throwing: URLError(.badServerResponse))
        }
        let response = HTTPClientResponse(status: .ok, body: .stream(stream))
        let prober = ProviderNamespaceProber(transport: RecordingGatewayTransport(responses: [response]))

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == .unknown)
    }

    @Test("A transport failure stays unknown and never fails the save")
    func transportFailureStaysUnknown() async throws {
        let prober = ProviderNamespaceProber(transport: NamespaceFailingTransport())

        let probe = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(probe.verdict == .unknown)
    }

    @Test("Cancellation propagates instead of masquerading as an unknown verdict")
    func cancellationPropagates() async throws {
        let prober = ProviderNamespaceProber(transport: CancellingGatewayTransport())

        await #expect(throws: CancellationError.self) {
            _ = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")
        }
    }

    @Test("The probe bound reaches the transport's per-request entry point")
    func probeBoundReachesPerRequestExecute() async throws {
        let transport = NamespaceTimeoutTransport()
        let prober = ProviderNamespaceProber(transport: transport)

        _ = try await prober.probe(provider: Self.probeProvider(), secret: nil, model: "m")

        #expect(await transport.receivedTimeouts == [.seconds(8)])
    }
}

private struct NamespaceFailingTransport: UpstreamTransport {
    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        throw URLError(.timedOut)
    }
}

private actor NamespaceTimeoutTransport: UpstreamTransport {
    private(set) var receivedTimeouts: [TimeAmount] = []

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        throw URLError(.timedOut)
    }

    func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse {
        receivedTimeouts.append(timeout)
        throw URLError(.timedOut)
    }
}
