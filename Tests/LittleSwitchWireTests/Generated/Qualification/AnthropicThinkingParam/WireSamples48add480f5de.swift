// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ThinkingBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples48add480f5de {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicThinkingParam.minimal",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.null:signature",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": null,
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["signature"])
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.missing:thinking",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.missingField, path: ["thinking"])
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.null:thinking",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"thinking\": null,
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["thinking"])
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"thinking\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"thinking\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicThinkingParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingParam.collision",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["signature"])
        ) { json in
            var value = try AnthropicThinkingParam(wireJSON: json)
            value.additionalFields["signature"] = .null
            return try value.wireJSON()
        },
    ]
}
