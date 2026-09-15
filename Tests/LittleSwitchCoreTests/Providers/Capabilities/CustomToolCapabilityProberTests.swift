import AsyncHTTPClient
import Foundation
import LittleSwitchCommon
import LittleSwitchTransport
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Custom tool semantic capability")
struct CustomToolCapabilityProberTests {
    @Test("An exact native marker skips fallback and replaces private request context", arguments: wires)
    func native(wire: ProviderToolContract.Wire) async throws {
        let transport = CustomCapabilityProbeTransport([.echo])
        let result = try await CustomToolCapabilityProber(transport: transport)
            .probe(template: customCapabilityTemplate(wire: wire), modelID: "model", wire: wire)
        #expect(result == .native)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url == customCapabilityTemplate(wire: wire).url)
        #expect(request.headers["authorization"] == ["Bearer synthetic-key"])
        #expect(request.headers["x-api-key"] == ["synthetic-api-key"])
        #expect(request.headers["openai-organization"] == ["synthetic-org"])
        #expect(request.headers["x-client-session"].isEmpty)
        #expect(request.headers["cookie"].isEmpty)
        #expect(request.headers["x-codex-turn-metadata"].isEmpty)
        #expect(request.headers["content-length"].isEmpty)
        #expect(try !#require(String(data: request.body, encoding: .utf8)).contains("private-"))
        let root = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(root["stream"] as? Bool == false)
        #expect(root["model"] as? String == "model")
        if wire == .responses {
            #expect(
                root["tool_choice"] as? [String: String] == ["type": "custom", "name": "littleswitch_custom_probe"])
        } else {
            let choice = try #require(root["tool_choice"] as? [String: Any])
            #expect(choice.count == 2 && choice["type"] as? String == "custom")
            #expect(choice["custom"] as? [String: String] == ["name": "littleswitch_custom_probe"])
        }
        #expect(root[wire == .responses ? "max_output_tokens" : "max_tokens"] as? Int == 256)
        #expect(root["previous_response_id"] == nil && root["store"] as? Bool != true)
        if wire == .responses { #expect((root["reasoning"] as? [String: String])?["effort"] == "minimal") }
        #expect(await transport.timeouts == [.seconds(15)])
    }

    @Test("Completed absence requires a successful strict function marker", arguments: wires)
    func functionFallback(wire: ProviderToolContract.Wire) async throws {
        let transport = CustomCapabilityProbeTransport([.noCall, .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(wire: wire), modelID: "model", wire: wire)
                == .functionEnvelope)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let root = try WireJSONCompatibility.fields(try #require(requests.last).body)
        if wire == .responses {
            #expect(
                root["tool_choice"] as? [String: String] == ["type": "function", "name": "littleswitch_custom_probe"])
        } else {
            let choice = try #require(root["tool_choice"] as? [String: Any])
            #expect(choice.count == 2 && choice["type"] as? String == "function")
            #expect(choice["function"] as? [String: String] == ["name": "littleswitch_custom_probe"])
        }
        let declaration = try #require((root["tools"] as? [[String: Any]])?.first)
        #expect(declaration["type"] as? String == "function")
        let function = wire == .responses ? declaration : try #require(declaration["function"] as? [String: Any])
        #expect(function["strict"] as? Bool == true)
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["required"] as? [String] == ["input"])
        #expect(parameters["additionalProperties"] as? Bool == false)
        let properties = try #require(parameters["properties"] as? [String: [String: String]])
        #expect(properties == ["input": ["type": "string"]])
    }

    @Test("z.ai's exact custom type rejection allows the function witness")
    func zaiRejection() async throws {
        let transport = CustomCapabilityProbeTransport([
            .http(400, #"{"error":{"code":"1214","message":"tools[0].type:type is illegal"}}"#), .echo,
        ])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(
                    template: customCapabilityTemplate(wire: .chatCompletions), modelID: "glm", wire: .chatCompletions)
                == .functionEnvelope)
    }

    @Test("Uncertain native results neither downgrade nor run the function probe", arguments: uncertainSteps)
    func inconclusive(step: CustomCapabilityProbeStep) async throws {
        let transport = CustomCapabilityProbeTransport([step, .echo])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses) == .inconclusive)
        #expect(await transport.requests.count == 1)
    }

    @Test("The fallback must decode the owned input envelope exactly", arguments: wires)
    func invalidEnvelope(wire: ProviderToolContract.Wire) async throws {
        let transport = CustomCapabilityProbeTransport([.noCall, .invalidEnvelope])
        #expect(
            try await CustomToolCapabilityProber(transport: transport)
                .probe(template: customCapabilityTemplate(wire: wire), modelID: "model", wire: wire) == .inconclusive)
    }

    @Test("Anthropic is never probed and caller cancellation propagates")
    func bypassAndCancellation() async throws {
        let transport = CustomCapabilityProbeTransport([.cancellation])
        let prober = CustomToolCapabilityProber(transport: transport)
        #expect(
            try await prober.probe(template: customCapabilityTemplate(), modelID: "model", wire: .anthropic)
                == .inconclusive)
        #expect(await transport.requests.isEmpty)
        await #expect(throws: CancellationError.self) {
            try await prober.probe(template: customCapabilityTemplate(), modelID: "model", wire: .responses)
        }
    }

    private static let wires: [ProviderToolContract.Wire] = [.responses, .chatCompletions]
    private static let uncertainSteps: [CustomCapabilityProbeStep] = [
        .http(401, "{}"), .http(403, "{}"), .http(429, "{}"), .http(500, "{}"),
        .http(400, #"{"error":{"message":"invalid request"}}"#),
        .http(400, #"{"error":{"code":"1214","message":"messages[0].content:type is illegal"}}"#),
        .http(
            400,
            #"{"error":{"param":"tool_choice","message":"tool_choice=\"required\" requires at least one tool with type=\"function\"; "#
                + #"other built-in tool types cannot be forced."}}"#),
        .http(200, #"{"status":"completed","output":[],"usage":{"output_tokens":256}}"#),
        .incomplete, .wrongMarker, .oversized, .transportFailure,
    ]
}
