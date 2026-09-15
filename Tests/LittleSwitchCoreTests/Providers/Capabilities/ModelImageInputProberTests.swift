import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("One-shot image probe")
struct ModelImageInputProberTests {
    @Test(
        "One request uses the resolved wire, a synthetic image and a small token budget",
        arguments: [ModelImageInputWire.responses, .chatCompletions])
    func request(wire: ModelImageInputWire) async throws {
        let transport = RecordingGatewayTransport(responses: [
            response(
                status: .ok,
                body: try #require(String(data: ModelImageProbeFixture.answer(wire: wire), encoding: .utf8)))
        ])
        let prober = ModelImageInputProber(transport: transport, challenge: Self.challenge)
        let result = try await prober.probe(
            provider: provider, model: DiscoveredModel(id: "model"), wire: wire, secret: "synthetic-key")
        #expect(result.outcome == .verified)
        #expect(result.usage == nil)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        let root = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(root["model"] as? String == "model")
        #expect(root["stream"] as? Bool == false)
        #expect(root[wire == .responses ? "max_output_tokens" : "max_tokens"] as? Int == 256)
        #expect(root["tools"] == nil && root["reasoning"] == nil && root["temperature"] == nil)
        #expect(request.headers["authorization"] == ["Bearer synthetic-key"])
        #expect(request.body.count <= 16 * 1_024)
        #expect(request.url == "https://provider.example/v1/\(wire == .responses ? "responses" : "chat/completions")")
        let messages = try #require(root[wire == .responses ? "input" : "messages"] as? [[String: Any]])
        let parts = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(!(parts[0]["text"] as? String ?? "").contains("white white yellow black"))
        let image =
            wire == .responses
            ? parts[1]["image_url"] as? String : (parts[1]["image_url"] as? [String: Any])?["url"] as? String
        #expect(image?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test("Timeout witness is bounded and failures do not retry")
    func timeout() async throws {
        let transport = ImageTimeoutTransport()
        let prober = ModelImageInputProber(transport: transport, challenge: Self.challenge)
        let result = try await prober.probe(
            provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        #expect(result.outcome == .inconclusive(.timeout))
        #expect(await transport.timeouts == [.seconds(15)])
    }

    @Test(
        "HTTP client read and request deadlines remain timeouts rather than connection failures",
        arguments: [HTTPClientError.deadlineExceeded, .readTimeout])
    func httpClientTimeout(error: HTTPClientError) async throws {
        let instant = Date(timeIntervalSince1970: 1_000)
        let now: @Sendable () -> Date = { instant }
        let prober = ModelImageInputProber(
            transport: ImageHTTPFailureTransport(error: error), challenge: Self.challenge, now: now)
        let result = try await prober.probe(
            provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        #expect(
            result
                == ModelImageInputProbeResult(
                    outcome: .inconclusive(.timeout), usage: nil, startedAt: instant, durationSeconds: 0))
    }

    @Test("Oversized response is inconclusive and cancellation propagates")
    func failureBounds() async throws {
        let large = RecordingGatewayTransport(responses: [
            response(status: .ok, body: String(repeating: "x", count: 32 * 1_024 + 1))
        ])
        let result = try await ModelImageInputProber(transport: large, challenge: Self.challenge)
            .probe(provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        #expect(result.outcome == .inconclusive(.sizeLimit))
        let cancelled = ModelImageInputProber(transport: CancellingGatewayTransport(), challenge: Self.challenge)
        await #expect(throws: CancellationError.self) {
            try await cancelled.probe(
                provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        }
    }

    @Test("The whole deadline also cancels a body stalled after response headers")
    func bodyDeadline() async throws {
        let transport = ImageStalledBodyTransport()
        let deadline: @Sendable () async throws -> Void = { await transport.waitForHeaders() }
        let prober = ModelImageInputProber(
            transport: transport, challenge: Self.challenge, waitForDeadline: deadline)
        let result = try await prober.probe(
            provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        #expect(result.outcome == .inconclusive(.timeout))
        #expect(await transport.calls == 1)
    }

    @Test("The request size bound avoids any network call")
    func requestSize() async throws {
        let transport = RecordingGatewayTransport(responses: [])
        let largeChallenge: @Sendable () -> ModelImageProbeChallenge = {
            ModelImageProbeChallenge(png: Data(repeating: 0, count: 16 * 1_024), expectedColors: [])
        }
        let prober = ModelImageInputProber(transport: transport, challenge: largeChallenge)
        let result = try await prober.probe(
            provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        #expect(result.outcome == .inconclusive(.sizeLimit))
        #expect(await transport.requests.isEmpty)
    }

    @Test("An incorrect billed answer keeps usage without retrying or falling back")
    func billedWrongAnswer() async throws {
        let body = #"{"status":"completed","output":[],"usage":{"input_tokens":100,"output_tokens":12}}"#
        let transport = RecordingGatewayTransport(responses: [response(status: .ok, body: body)])
        let result = try await ModelImageInputProber(transport: transport, challenge: Self.challenge)
            .probe(provider: provider, model: DiscoveredModel(id: "model"), wire: .responses, secret: nil)
        #expect(result.outcome == .inconclusive(.wrongAnswer))
        #expect(result.usage == ResponsesUsage(inputTokens: 100, outputTokens: 12))
        #expect(await transport.requests.count == 1)
    }

    private var provider: Provider { Provider(name: "Example", baseURL: "https://provider.example", authMode: .bearer) }

    private static func challenge() throws -> ModelImageProbeChallenge {
        try ModelImageProbeChallenge.make(colors: ModelImageProbeFixture.colors)
    }
}

private actor ImageStalledBodyTransport: UpstreamTransport {
    private(set) var calls = 0
    private var waiting: CheckedContinuation<Void, Never>?

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        calls += 1
        waiting?.resume()
        waiting = nil
        let stream = AsyncThrowingStream<ByteBuffer, any Error> {
            try await Task.sleep(for: .seconds(60))
            return nil
        }
        return HTTPClientResponse(status: .ok, headers: [:], body: .stream(stream))
    }

    func waitForHeaders() async {
        if calls == 0 { await withCheckedContinuation { waiting = $0 } }
    }
}

private actor ImageTimeoutTransport: UpstreamTransport {
    private(set) var timeouts: [TimeAmount] = []

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        throw URLError(.unknown)
    }

    func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse {
        timeouts.append(timeout)
        throw URLError(.timedOut)
    }
}

private struct ImageHTTPFailureTransport: UpstreamTransport {
    let error: HTTPClientError

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse { throw error }
}
