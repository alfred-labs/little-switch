// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ThinkingBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9f8630f5a727 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicThinkingBlock.minimal",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.full",
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
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.null:signature",
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
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.missing:thinking",
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
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.null:thinking",
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
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.missing:type",
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
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.null:type",
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
            return try AnthropicThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingBlock.collision",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["signature"])
        ) { json in
            var value = try AnthropicThinkingBlock(wireJSON: json)
            value.additionalFields["signature"] = .null
            return try value.wireJSON()
        },
    ]
}
