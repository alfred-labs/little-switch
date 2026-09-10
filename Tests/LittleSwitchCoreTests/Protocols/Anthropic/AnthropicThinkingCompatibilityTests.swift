import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic thinking compatibility")
struct AnthropicThinkingCompatibilityTests {
    @Test("Disabled thinking gains only low effort", arguments: [false, true])
    func addsOnlyLowEffort(existingOutputConfiguration: Bool) throws {
        let request = Data(
            #"""
            {
              "model": "any-model",
              "thinking": {"type": "disabled", "budget_tokens": 1024, "opaque": true},
              "max_tokens": 8192,
              "stream": true,
              "system": [{"type": "text", "text": "system", "cache_control": {"type": "ephemeral"}}],
              "messages": [{"role": "user", "content": [{"type": "text", "text": "hello"}]}],
              "tools": [{"name": "weather", "input_schema": {"type": "object"}}],
              "stop_sequences": ["end"],
              "metadata": {"unknown": null},
              "unknown": [1, "value", false]
            }
            """#.utf8
        )
        var original = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
        let format: [String: Any] = ["type": "json_schema", "schema": ["type": "object"]]
        if existingOutputConfiguration {
            original["output_config"] = ["format": format, "opaque": true]
        }
        let body = try JSONSerialization.data(withJSONObject: original)
        var expected = original
        var expectedOutput = original["output_config"] as? [String: Any] ?? [:]
        expectedOutput["effort"] = "low"
        expected["output_config"] = expectedOutput

        let adapted = try AnthropicThinkingCompatibility.applying(.lowEffort, to: body)

        #expect(try JSONSerialization.jsonObject(with: adapted) as? NSDictionary == expected as NSDictionary)
        #expect(try AnthropicThinkingCompatibility.applying(.lowEffort, to: adapted) == adapted)
    }

    @Test(
        "Explicit efforts retain the request bytes, including null and unfamiliar values",
        arguments: [#""low""#, #""medium""#, #""high""#, #""future-effort""#, "null", "false", "0", "{}", "[]"],
        ["output_config", "reasoning_effort"]
    )
    func preservesExplicitEffort(effort: String, location: String) throws {
        let field =
            location == "output_config" ? #""output_config":{"effort":\#(effort)}"# : #""reasoning_effort":\#(effort)"#
        let body = Data(" \n{\"thinking\":{\"type\":\"disabled\"},\(field)}\t".utf8)

        #expect(try AnthropicThinkingCompatibility.applying(.lowEffort, to: body) == body)
    }

    @Test(
        "Absent, enabled, adaptive and malformed thinking retain the request bytes",
        arguments: [
            #"{}"#,
            #"{"thinking":{"type":"enabled","budget_tokens":1024}}"#,
            #"{"thinking":{"type":"adaptive"}}"#,
            #"{"thinking":{"type":"Disabled"}}"#,
            #"{"thinking":{"type":"disabled "}}"#,
            #"{"thinking":{"type":null}}"#,
            #"{"thinking":{"type":false}}"#,
            #"{"thinking":{}}"#,
            #"{"thinking":null}"#,
            #"{"thinking":"disabled"}"#,
            #"{"thinking":[]}"#,
            #"{"thinking":1}"#,
            #"{"messages":[{"thinking":{"type":"disabled"}}]}"#,
            #"[{"thinking":{"type":"disabled"}}]"#,
            "null", "false", "42", "{", "",
        ]
    )
    func preservesOtherThinking(json: String) throws {
        let body = Data(" \n\(json)\t".utf8)
        #expect(try AnthropicThinkingCompatibility.applying(.lowEffort, to: body) == body)
    }

    @Test(
        "Malformed output configuration retains the request bytes",
        arguments: ["null", "[]", #""value""#, "false", "42"])
    func preservesMalformedOutputConfiguration(value: String) throws {
        let body = Data(#" {"thinking":{"type":"disabled"},"output_config":\#(value)} "#.utf8)
        #expect(try AnthropicThinkingCompatibility.applying(.lowEffort, to: body) == body)
    }

    @Test(
        "Pass through retains even eligible and malformed requests byte for byte",
        arguments: [#"{"thinking":{"type":"disabled"}}"#, "{"])
    func absentOverride(json: String) throws {
        let body = Data(" \n\(json)\t".utf8)
        #expect(
            try AnthropicThinkingCompatibility.applying(
                ProviderDisabledThinkingOverride.passthrough, to: body) == body)
    }
}
