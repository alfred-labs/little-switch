// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/RedactedThinkingBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples298b24e08689 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicRedactedThinkingParam.minimal",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.missing:data",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: .init(.missingField, path: ["data"])
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.null:data",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": null,
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["data"])
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicRedactedThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingParam.collision",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["data"])
        ) { json in
            var value = try AnthropicRedactedThinkingParam(wireJSON: json)
            value.additionalFields["data"] = .null
            return try value.wireJSON()
        },
    ]
}
