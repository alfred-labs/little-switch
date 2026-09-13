// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Usage
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: c4a71a16dacdddda5aabdc87a187a0994f0609d4dd740cfa0faa458ee384bb71
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples6562b154a6c0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicUsageFields.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": {
                    \"ephemeral_1h_input_tokens\": 9007199254740993,
                    \"ephemeral_5m_input_tokens\": 9007199254740993
                  },
                  \"cache_creation_input_tokens\": 9007199254740993,
                  \"cache_read_input_tokens\": 9007199254740993,
                  \"input_tokens\": 9007199254740993,
                  \"output_tokens\": 9007199254740993,
                  \"service_tier\": \"standard\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.null:cache_creation",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": null,
                  \"cache_creation_input_tokens\": 9007199254740993,
                  \"cache_read_input_tokens\": 9007199254740993,
                  \"input_tokens\": 9007199254740993,
                  \"output_tokens\": 9007199254740993,
                  \"service_tier\": \"standard\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.null:cache_creation_input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": {
                    \"ephemeral_1h_input_tokens\": 9007199254740993,
                    \"ephemeral_5m_input_tokens\": 9007199254740993
                  },
                  \"cache_creation_input_tokens\": null,
                  \"cache_read_input_tokens\": 9007199254740993,
                  \"input_tokens\": 9007199254740993,
                  \"output_tokens\": 9007199254740993,
                  \"service_tier\": \"standard\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.null:cache_read_input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": {
                    \"ephemeral_1h_input_tokens\": 9007199254740993,
                    \"ephemeral_5m_input_tokens\": 9007199254740993
                  },
                  \"cache_creation_input_tokens\": 9007199254740993,
                  \"cache_read_input_tokens\": null,
                  \"input_tokens\": 9007199254740993,
                  \"output_tokens\": 9007199254740993,
                  \"service_tier\": \"standard\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.null:input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": {
                    \"ephemeral_1h_input_tokens\": 9007199254740993,
                    \"ephemeral_5m_input_tokens\": 9007199254740993
                  },
                  \"cache_creation_input_tokens\": 9007199254740993,
                  \"cache_read_input_tokens\": 9007199254740993,
                  \"input_tokens\": null,
                  \"output_tokens\": 9007199254740993,
                  \"service_tier\": \"standard\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.null:output_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": {
                    \"ephemeral_1h_input_tokens\": 9007199254740993,
                    \"ephemeral_5m_input_tokens\": 9007199254740993
                  },
                  \"cache_creation_input_tokens\": 9007199254740993,
                  \"cache_read_input_tokens\": 9007199254740993,
                  \"input_tokens\": 9007199254740993,
                  \"output_tokens\": null,
                  \"service_tier\": \"standard\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.null:service_tier",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_creation\": {
                    \"ephemeral_1h_input_tokens\": 9007199254740993,
                    \"ephemeral_5m_input_tokens\": 9007199254740993
                  },
                  \"cache_creation_input_tokens\": 9007199254740993,
                  \"cache_read_input_tokens\": 9007199254740993,
                  \"input_tokens\": 9007199254740993,
                  \"output_tokens\": 9007199254740993,
                  \"service_tier\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicUsageFields(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicUsageFields.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["cache_creation"])
        ) { json in
            var value = try AnthropicUsageFields(wireJSON: json)
            value.additionalFields["cache_creation"] = .null
            return try value.wireJSON()
        },
    ]
}
