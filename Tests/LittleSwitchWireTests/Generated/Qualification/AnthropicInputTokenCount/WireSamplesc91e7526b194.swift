// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Usage
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: b3eb6c162cb75582e34df3c7d3efb51884d88d7fc9f1203ce4cdf050b34482cc
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc91e7526b194 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicInputTokenCount.minimal",
            input: """
                {
                  \"input_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputTokenCount(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputTokenCount.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputTokenCount(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputTokenCount.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicInputTokenCount(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputTokenCount.missing:input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["input_tokens"])
        ) { json in
            return try AnthropicInputTokenCount(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputTokenCount.null:input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["input_tokens"])
        ) { json in
            return try AnthropicInputTokenCount(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputTokenCount.collision",
            input: """
                {
                  \"input_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input_tokens"])
        ) { json in
            var value = try AnthropicInputTokenCount(wireJSON: json)
            value.additionalFields["input_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
