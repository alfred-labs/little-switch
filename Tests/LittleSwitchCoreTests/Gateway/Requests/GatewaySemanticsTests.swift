import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Gateway semantics")
struct GatewaySemanticsTests {
    @Test("Gateway serialization parses byte bodies only at the rewrite boundary")
    func gatewaySerializationBoundary() throws {
        let serializer = LiveGatewaySerializer()
        let body = Data(#"{"model":"public","input":"hello"}"#.utf8)

        for rewritten in [
            try serializer.rewriteMessage(body, modelID: "physical"),
            try serializer.rewriteResponses(body, modelID: "physical"),
        ] {
            let object = try #require(
                JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
            )
            #expect(object["model"] as? String == "physical")
            #expect(object["input"] as? String == "hello")
        }
        #expect(throws: (any Swift.Error).self) {
            try serializer.rewriteMessage(Data("{".utf8), modelID: "physical")
        }
        #expect(throws: (any Swift.Error).self) {
            try serializer.rewriteResponses(Data("[]".utf8), modelID: "physical")
        }
    }

    @Test("The token estimator ignores transport controls and counts semantic content")
    func tokenEstimate() throws {
        let empty = try TokenEstimator.estimate(Data(#"{"model":"claude-opus-5","stream":true,"max_tokens":100}"#.utf8))
        #expect(empty == 0)

        let request = Data(
            #"""
            {
              "model": "claude-opus-5",
              "system": "Be exact",
              "messages": [{
                "role": "user",
                "content": [
                  {"type": "text", "text": "Hello world"},
                  {"type": "image", "source": {"data": "huge"}}
                ]
              }],
              "tools": [{
                "name": "weather",
                "description": "Forecast",
                "input_schema": {
                  "type": "object",
                  "properties": {"city": {"type": "string"}}
                }
              }]
            }
            """#
            .utf8)
        let estimate = try TokenEstimator.estimate(request)
        #expect(estimate > 1)
        #expect(estimate < 100)
    }

    @Test("The token estimator rejects malformed JSON")
    func tokenEstimateRejectsMalformedJSON() {
        #expect(throws: (any Swift.Error).self) {
            try TokenEstimator.estimate(Data("{".utf8))
        }
        #expect(throws: TokenEstimator.Error.self) {
            try TokenEstimator.estimate(Data("[]".utf8))
        }
    }

    @Test("The token estimator includes JSON numbers and ignores null values")
    func tokenEstimateNumbers() throws {
        let request = Data(
            #"{"system":12345,"messages":[{"role":"user","content":null}]}"#.utf8
        )
        #expect(try TokenEstimator.estimate(request) > 0)
    }

    @Test(
        "Only a structured unsupported-image response requests a retry",
        arguments: [
            (
                400,
                #"{"type":"error","error":{"type":"invalid_request_error","message":"This model does not support image input"}}"#,
                true
            ),
            (
                400, #"{"type":"error","error":{"type":"invalid_request_error","message":"Vision is unsupported"}}"#,
                true
            ),
            (
                400, #"{"type":"error","error":{"type":"invalid_request_error","message":"The image is malformed"}}"#,
                false
            ),
            (400, #"{"type":"error","error":{"type":"authentication_error","message":"Images unsupported"}}"#, false),
            (401, #"{"type":"error","error":{"type":"invalid_request_error","message":"Images unsupported"}}"#, false),
            (400, "not-json", false),
        ]
    )
    func imageRetryPredicate(status: Int, response: String, expected: Bool) throws {
        let replacement = try ImageFallback.replacingImages(in: imageRequest())
        let request = try #require(replacement)
        #expect(request.didReplace)
        #expect(
            ImageFallback.shouldRetry(
                status: status,
                responseBody: Data(response.utf8),
                originalRequest: imageRequest()
            ) == expected
        )
    }

    @Test("Image replacement handles nested tool results and preserves other fields")
    func imageReplacement() throws {
        let replacement = try ImageFallback.replacingImages(in: imageRequest())
        let result = try #require(replacement)
        #expect(result.didReplace)
        let root = try #require(JSONSerialization.jsonObject(with: result.body) as? [String: Any])
        #expect(root["model"] as? String == "claude-opus-5")
        let serialized = try #require(String(data: result.body, encoding: .utf8))
        #expect(!serialized.contains("base64-secret"))
        #expect(serialized.components(separatedBy: ImageFallback.notice).count - 1 == 2)
        #expect(serialized.contains("keep me"))
    }

    @Test("Image-free requests are not rewritten or retried")
    func imageFreeRequest() throws {
        let request = Data(#"{"model":"claude-opus-5","messages":[{"role":"user","content":"hello"}]}"#.utf8)
        #expect(try ImageFallback.replacingImages(in: request) == nil)
        #expect(
            !ImageFallback.shouldRetry(
                status: 400,
                responseBody: Data(
                    #"{"type":"error","error":{"type":"invalid_request_error","message":"Images unsupported"}}"#.utf8),
                originalRequest: request
            ))
    }

    @Test("Malformed image requests fail rewriting safely")
    func malformedImageRequest() {
        for source in ["{", "null", "true", "1", #""text""#] {
            #expect(throws: (any Swift.Error).self) {
                try ImageFallback.replacingImages(in: Data(source.utf8))
            }
        }
    }

    @Test("Catalog labels append the configured indicator to plain names")
    func catalogLabels() throws {
        let route = try #require(ClaudeRoute.all.first { $0.id == "claude-opus-5" })
        #expect(route.catalogDisplayName(indicator: .equilibrium) == "Opus ⇌")
        #expect(route.catalogDisplayName(indicator: .swap) == "Opus ⇄")
        #expect(route.catalogDisplayName(indicator: .routed) == "Opus ⇢")
        #expect(route.catalogDisplayName(indicator: .mapsTo) == "Opus ↦")
        #expect(route.catalogDisplayName(indicator: .none) == "Opus")
    }

    @Test("Model indicator options expose every symbol")
    func modelIndicatorOptions() {
        let symbols: [String?] = ModelIndicator.allCases.map(\.symbol)
        #expect(symbols == [nil, "⇄", "⇌", "⇢", "↦"])
    }

    @Test("Catalog JSON advertises only valid mapped routes in public order")
    func catalog() throws {
        let firstID = UUID()
        let secondID = UUID()
        let snapshot = RoutingSnapshot(
            generation: 3,
            providers: [
                Provider(
                    id: firstID,
                    name: "z.ai",
                    baseURL: "https://api.z.ai/api/anthropic",
                    authMode: .bearer,
                    models: [
                        DiscoveredModel(
                            id: "glm",
                            maxTokens: 131_072,
                            detectedContextWindow: 1_000_000
                        )
                    ]
                ),
                Provider(
                    id: secondID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    models: [DiscoveredModel(id: "qwen", detectedContextWindow: 400_000)]
                ),
            ],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: firstID, modelID: "glm"),
                "claude-sonnet-5": ModelMapping(providerID: secondID, modelID: "qwen"),
            ]
        )
        let response = ClaudeCatalog.make(from: snapshot)
        #expect(response.data.map(\.id) == ["claude-opus-5", "claude-sonnet-5"])
        #expect(response.data.map(\.displayName) == ["Opus ↦", "Sonnet ↦"])
        #expect(response.data.map(\.maxTokens) == [64_000, 64_000])
        #expect(response.data.map(\.maxInputTokens) == [200_000, 200_000])
        // Token limits are fixed; 1M support stays honest per mapped model.
        #expect(response.data.map(\.supports1M) == [true, false])
        #expect(response.firstID == "claude-opus-5")
        #expect(response.lastID == "claude-sonnet-5")
        #expect(!response.hasMore)

        let data = try ClaudeCatalog.encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["first_id"] as? String == "claude-opus-5")
        let entries = try #require(object["data"] as? [[String: Any]])
        #expect(entries.first?["max_input_tokens"] as? Int == 200_000)
        #expect(entries.first?["supports_1m"] as? Bool == true)
    }

    @Test("Catalog JSON is byte-identical after remapping routes to other providers")
    func catalogInvariance() throws {
        let firstID = UUID()
        let secondID = UUID()
        let zai = Provider(
            id: firstID,
            name: "z.ai",
            baseURL: "https://api.z.ai/api/anthropic",
            authMode: .bearer,
            models: [
                DiscoveredModel(
                    id: "glm",
                    maxTokens: 131_072,
                    detectedContextWindow: 1_000_000
                )
            ]
        )
        let local = Provider(
            id: secondID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: .none,
            models: [DiscoveredModel(id: "qwen", detectedContextWindow: 400_000)]
        )
        let original = RoutingSnapshot(
            generation: 1,
            providers: [zai, local],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: firstID, modelID: "glm"),
                "claude-sonnet-5": ModelMapping(providerID: secondID, modelID: "qwen"),
            ]
        )
        let remapped = RoutingSnapshot(
            generation: 2,
            providers: [zai, local],
            mappings: [
                "claude-opus-5": ModelMapping(providerID: secondID, modelID: "qwen"),
                "claude-sonnet-5": ModelMapping(providerID: firstID, modelID: "glm"),
            ]
        )

        let originalResponse = ClaudeCatalog.make(from: original)
        let remappedResponse = ClaudeCatalog.make(from: remapped)

        // Identity covers what clients display: route IDs and advertised
        // names never move with the physical target.
        #expect(
            remappedResponse.data.map(\.displayName)
                == originalResponse.data.map(\.displayName)
        )
        #expect(
            remappedResponse.data.map(\.id) == originalResponse.data.map(\.id)
        )
        // Capabilities follow the physical targets they describe.
        #expect(originalResponse.data.map(\.supports1M) == [true, false])
        #expect(remappedResponse.data.map(\.supports1M) == [false, true])
    }

    private func imageRequest() -> Data {
        Data(
            #"""
            {
              "model": "claude-opus-5",
              "messages": [{
                "role": "user",
                "content": [
                  {"type": "text", "text": "keep me"},
                  {
                    "type": "image",
                    "source": {"type": "base64", "data": "base64-secret"}
                  },
                  {
                    "type": "tool_result",
                    "tool_use_id": "1",
                    "content": [{
                      "type": "image",
                      "source": {"data": "base64-secret"}
                    }]
                  }
                ]
              }]
            }
            """#
            .utf8)
    }
}
