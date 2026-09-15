import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom capability probe boundaries")
struct CustomToolCapabilityProbeBoundsTests {
    @Test("The total deadline cancels a body stalled after response headers")
    func deadline() async throws {
        let transport = CustomCapabilityStalledTransport()
        let prober = CustomToolCapabilityProber(transport: transport) { await transport.waitForHeaders() }
        #expect(
            try await prober.probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses)
                == .inconclusive)
        #expect(await transport.calls == 1)
    }

    @Test("A new witness gets a fresh synthetic marker")
    func freshMarker() async throws {
        let transport = CustomCapabilityProbeTransport([.echo, .echo])
        let prober = CustomToolCapabilityProber(transport: transport)
        _ = try await prober.probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses)
        _ = try await prober.probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].body != requests[1].body)
    }

    @Test("z.ai Chat disables thinking within the small token budget")
    func zaiThinking() async throws {
        let transport = CustomCapabilityProbeTransport([.echo])
        let template = HTTPClientRequest(url: "https://api.z.ai/api/coding/paas/v4/chat/completions")
        _ = try await CustomToolCapabilityProber(transport: transport).probe(
            template: template, modelID: "glm", wire: .chatCompletions)
        let body = try #require(await transport.requests.first).body
        let root = try WireJSONCompatibility.fields(body)
        #expect(root["thinking"] as? [String: String] == ["type": "disabled"])
    }

    @Test("Both wires stop on native truncation", arguments: [ProviderToolContract.Wire.responses, .chatCompletions])
    func truncated(wire: ProviderToolContract.Wire) async throws {
        let transport = CustomCapabilityProbeTransport([.incomplete, .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(wire: wire), modelID: "model", wire: wire) == .inconclusive)
        #expect(await transport.requests.count == 1)
    }

    @Test("Explicit custom type rejections allow only one fallback", arguments: rejections)
    func explicitRejection(body: String) async throws {
        let transport = CustomCapabilityProbeTransport([.http(400, body), .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .functionEnvelope)
        #expect(await transport.requests.count == 2)
    }

    @Test("Unsuccessful function witnesses remain inconclusive", arguments: fallbackFailures)
    func fallbackFailure(step: CustomCapabilityProbeStep) async throws {
        let transport = CustomCapabilityProbeTransport([.noCall, step])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .inconclusive)
        #expect(await transport.requests.count == 2)
    }

    @Test("An explicit optional reasoning rejection retries the same witness without reasoning")
    func optionalReasoningRejection() async throws {
        let rejection =
            #"{"error":{"param":"reasoning.effort","code":"unsupported_parameter","message":"Unsupported parameter: 'reasoning.effort'."}}"#
        let transport = CustomCapabilityProbeTransport([.http(400, rejection), .noCall, .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .functionEnvelope)
        let requests = await transport.requests
        try #require(requests.count == 3)
        let first = try WireJSONCompatibility.fields(requests[0].body)
        let retry = try WireJSONCompatibility.fields(requests[1].body)
        #expect(first["reasoning"] != nil && retry["reasoning"] == nil)
        #expect(first["input"] as? [[String: String]] == retry["input"] as? [[String: String]])
        #expect((try WireJSONCompatibility.fields(requests[2].body))["reasoning"] != nil)
    }

    @Test("Optional-control retries are limited to one per witness")
    func repeatedOptionalRejection() async throws {
        let rejection =
            #"{"error":{"param":"reasoning","code":"unsupported_parameter","message":"Unsupported parameter: 'reasoning'."}}"#
        let transport = CustomCapabilityProbeTransport([.http(400, rejection), .http(400, rejection), .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .inconclusive)
        #expect(await transport.requests.count == 2)
    }

    @Test("An explicit thinking rejection removes the z.ai extension")
    func optionalThinkingRejection() async throws {
        let rejection =
            #"{"error":{"param":"thinking","code":"unsupported_parameter","message":"Unsupported parameter: 'thinking'."}}"#
        let transport = CustomCapabilityProbeTransport([.http(400, rejection), .echo])
        let template = HTTPClientRequest(url: "https://api.z.ai/api/coding/paas/v4/chat/completions")
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: template, modelID: "glm", wire: .chatCompletions) == .native)
        let requests = await transport.requests
        try #require(requests.count == 2)
        #expect((try WireJSONCompatibility.fields(requests[1].body))["thinking"] == nil)
    }

    @Test("Incidental reasoning wording is not an optional-control rejection")
    func unrelatedReasoningRejection() async throws {
        let rejection = #"{"error":{"param":"tools[0].type","message":"invalid request for reasoning model"}}"#
        let transport = CustomCapabilityProbeTransport([.http(400, rejection), .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .inconclusive)
        #expect(await transport.requests.count == 1)
    }

    private static let rejections = [
        #"{"error":{"code":1214,"message":"tools[0].type:type is illegal"}}"#,
        #"{"error":{"param":"tools[0].type","message":"Unsupported value: 'custom'. Supported values are: 'function'."}}"#,
    ]
    private static let fallbackFailures: [CustomCapabilityProbeStep] = [
        .wrongMarker, .noCall, .incomplete, .http(401, "{}"), .http(429, "{}"), .http(503, "{}"), .transportFailure,
    ]
}

private actor CustomCapabilityStalledTransport: UpstreamTransport {
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
