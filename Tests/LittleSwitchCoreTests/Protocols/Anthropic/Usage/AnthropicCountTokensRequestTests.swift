import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic count-tokens request")
struct AnthropicCountTokensRequestTests {
    @Test("Projection keeps only token-bearing Anthropic fields")
    func projectsAllowlistedFields() throws {
        let input: [String: Any] = [
            "model": "xlarge",
            "messages": [
                [
                    "role": "user",
                    "content": [["type": "text", "text": "Bonjour 👋"]],
                ]
            ],
            "system": [["type": "text", "text": "Be precise"]],
            "tools": [
                [
                    "name": "lookup",
                    "description": "Look up a value",
                    "input_schema": ["type": "object"],
                ]
            ],
            "tool_choice": ["type": "auto"],
            "thinking": ["type": "enabled", "budget_tokens": 1_024],
            "output_config": ["effort": "high"],
            "cache_control": ["type": "ephemeral"],
            "stream": true,
            "max_tokens": 4_096,
            "temperature": 0.2,
            "top_p": 0.9,
            "top_k": 40,
            "metadata": ["user_id": "private"],
            "stop_sequences": ["STOP"],
        ]
        let inputData = try jsonData(input)

        let projected = try AnthropicCountTokensRequest.project(inputData)
        let object = try #require(
            JSONSerialization.jsonObject(with: projected) as? [String: Any]
        )

        #expect(
            Set(object.keys)
                == Set([
                    "model", "messages", "system", "tools", "tool_choice",
                    "thinking", "output_config", "cache_control",
                ])
        )
        #expect(object["model"] as? String == "xlarge")
        #expect(
            try jsonData(object)
                == jsonData([
                    "model": input["model"] as Any,
                    "messages": input["messages"] as Any,
                    "system": input["system"] as Any,
                    "tools": input["tools"] as Any,
                    "tool_choice": input["tool_choice"] as Any,
                    "thinking": input["thinking"] as Any,
                    "output_config": input["output_config"] as Any,
                    "cache_control": input["cache_control"] as Any,
                ])
        )
    }

    @Test("Projection requires an object with string model and messages array")
    func rejectsInvalidRequests() throws {
        let invalidBodies: [Data] = [
            Data("null".utf8),
            Data("[]".utf8),
            try jsonData(["messages": []]),
            try jsonData(["model": 7, "messages": []]),
            try jsonData(["model": "xlarge"]),
            try jsonData(["model": "xlarge", "messages": "hello"]),
            Data("{".utf8),
        ]

        for body in invalidBodies {
            #expect(throws: AnthropicCountTokensRequest.Error.invalidRequest) {
                try AnthropicCountTokensRequest.project(body)
            }
        }
    }

    @Test("Parser accepts a positive integral input token count")
    func parsesPositiveCount() throws {
        #expect(
            try AnthropicCountTokensRequest.parseCount(
                Data(#"{"input_tokens":321}"#.utf8)
            ) == 321
        )
    }

    @Test("Parser rejects every non-positive or non-integral response shape")
    func rejectsInvalidCounts() {
        let invalid = [
            "{}",
            #"{"input_tokens":true}"#,
            #"{"input_tokens":false}"#,
            #"{"input_tokens":0}"#,
            #"{"input_tokens":-1}"#,
            #"{"input_tokens":1.5}"#,
            #"{"input_tokens":"12"}"#,
            #"{"input_tokens":null}"#,
            #"{"input_tokens":9223372036854775808}"#,
            "[]",
            "null",
            "{",
        ]

        for json in invalid {
            #expect(throws: AnthropicCountTokensRequest.Error.invalidResponse) {
                try AnthropicCountTokensRequest.parseCount(Data(json.utf8))
            }
        }
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}
