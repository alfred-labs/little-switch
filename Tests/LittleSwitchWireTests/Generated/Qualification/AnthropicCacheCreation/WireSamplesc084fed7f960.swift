// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CacheCreation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: c4a71a16dacdddda5aabdc87a187a0994f0609d4dd740cfa0faa458ee384bb71
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc084fed7f960 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCacheCreation.minimal",
            input: """
                {
                  \"ephemeral_1h_input_tokens\": 9007199254740993,
                  \"ephemeral_5m_input_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"ephemeral_1h_input_tokens\": 1e400,
                  \"ephemeral_5m_input_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.missing:ephemeral_1h_input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"ephemeral_5m_input_tokens\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["ephemeral_1h_input_tokens"])
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.null:ephemeral_1h_input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"ephemeral_1h_input_tokens\": null,
                  \"ephemeral_5m_input_tokens\": 1e400
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["ephemeral_1h_input_tokens"])
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.missing:ephemeral_5m_input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"ephemeral_1h_input_tokens\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["ephemeral_5m_input_tokens"])
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.null:ephemeral_5m_input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"ephemeral_1h_input_tokens\": 1e400,
                  \"ephemeral_5m_input_tokens\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["ephemeral_5m_input_tokens"])
        ) { json in
            return try AnthropicCacheCreation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCacheCreation.collision",
            input: """
                {
                  \"ephemeral_1h_input_tokens\": 9007199254740993,
                  \"ephemeral_5m_input_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["ephemeral_1h_input_tokens"])
        ) { json in
            var value = try AnthropicCacheCreation(wireJSON: json)
            value.additionalFields["ephemeral_1h_input_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
