// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ThinkingBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 0256884472d43453981d722aaf99b4cf6fb8e448e657c9e96e2742daa727d3f1
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples34704c6a3607 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicIncomingThinkingBlock.minimal",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.full",
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
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.null:signature",
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
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.missing:thinking",
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
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.null:thinking",
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
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.missing:type",
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
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.null:type",
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
            return try AnthropicIncomingThinkingBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingThinkingBlock.collision",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["signature"])
        ) { json in
            var value = try AnthropicIncomingThinkingBlock(wireJSON: json)
            value.additionalFields["signature"] = .null
            return try value.wireJSON()
        },
    ]
}
