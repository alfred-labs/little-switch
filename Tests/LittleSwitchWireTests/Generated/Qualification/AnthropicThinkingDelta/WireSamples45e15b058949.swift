// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/ThinkingDelta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples45e15b058949 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicThinkingDelta.minimal",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.missing:thinking",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["thinking"])
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.null:thinking",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": null,
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["thinking"])
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicThinkingDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDelta.collision",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["thinking"])
        ) { json in
            var value = try AnthropicThinkingDelta(wireJSON: json)
            value.additionalFields["thinking"] = .null
            return try value.wireJSON()
        },
    ]
}
