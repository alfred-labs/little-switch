// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/RedactedThinkingBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesfa37c4f96141 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicRedactedThinkingBlock.minimal",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.full",
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
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.missing:data",
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
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.null:data",
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
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.missing:type",
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
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.null:type",
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
            return try AnthropicRedactedThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRedactedThinkingBlock.collision",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["data"])
        ) { json in
            var value = try AnthropicRedactedThinkingBlock(wireJSON: json)
            value.additionalFields["data"] = .null
            return try value.wireJSON()
        },
    ]
}
