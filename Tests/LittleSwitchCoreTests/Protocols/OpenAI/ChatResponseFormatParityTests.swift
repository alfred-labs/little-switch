import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Chat structured response format parity")
struct ChatResponseFormatParityTests {
    @Test("Text verbosity and structured format reach Chat together")
    func verbosityWithFormat() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: JSONSerialization.data(withJSONObject: [
                "model": "route", "input": "Review", "text": ["verbosity": "low", "format": ["type": "json_object"]],
            ]), targetModel: "xlarge")
        let request = try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
        #expect(request["verbosity"] as? String == "low")
        #expect(request["response_format"] as? [String: String] == ["type": "json_object"])
    }

    @Test("Shared request controls are preserved, including disabled storage")
    func sharedRequestControls() throws {
        let controls: [String: Any] = [
            "store": false, "metadata": ["case": "synthetic"], "user": "synthetic-user",
            "service_tier": "default", "safety_identifier": "synthetic-safety",
            "prompt_cache_key": "synthetic-prefix", "prompt_cache_retention": "24h",
            "prompt_cache_options": ["mode": "explicit", "ttl": "30m"],
        ]
        var root = controls
        root["model"] = "route"
        root["input"] = "Hello"
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: JSONSerialization.data(withJSONObject: root), targetModel: "xlarge")
        let request = try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
        #expect(request.filter { controls[$0.key] != nil } as NSDictionary == controls as NSDictionary)
    }

    @Test("Responses output schemas retain every constraint in Chat")
    func structuredResponseFormat() throws {
        let schema: [String: Any] = [
            "name": "review", "description": "A structured decision", "strict": true,
            "schema": [
                "type": "object", "properties": ["outcome": ["type": "string", "enum": ["allow", "deny"]]],
                "required": ["outcome"], "additionalProperties": false,
            ],
        ]
        var format = schema
        format["type"] = "json_schema"
        let request = try request(format: format)
        #expect(
            request["response_format"] as? NSDictionary == ["type": "json_schema", "json_schema": schema]
                as NSDictionary)
    }

    @Test("JSON object and plain text modes survive Chat conversion", arguments: ["json_object", "text"])
    func simpleResponseFormat(type: String) throws {
        #expect(try request(format: ["type": type])["response_format"] as? [String: String] == ["type": type])
    }

    @Test(
        "Malformed output schemas fail before dispatch",
        arguments: [
            ["type": "json_schema", "name": "review"],
            ["type": "unknown"],
        ])
    func rejectsMalformedResponseFormat(format: [String: String]) {
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
            _ = try request(format: format)
        }
    }

    @Test("Malformed format containers fail before dispatch")
    func rejectsMalformedFormatContainer() throws {
        for format: Any in ["json_schema", [String: String](), NSNull()] {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try request(format: format)
            }
        }
    }

    private func request(format: Any) throws -> [String: Any] {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: JSONSerialization.data(withJSONObject: [
                "model": "route", "input": "Review", "text": ["format": format],
            ]),
            targetModel: "xlarge"
        )
        return try #require(JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
    }
}
