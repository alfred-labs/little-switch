// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ThinkingConfigDisabled
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: fec4acfe2c5e4e5e6da8e260eae299ff0b3652ffcec38e650f98234cfeb9699b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples310cf1d2a6fe {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicDisabledThinking.minimal",
            input: """
                {
                  \"type\": \"disabled\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDisabledThinking(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDisabledThinking.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"disabled\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDisabledThinking(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDisabledThinking.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicDisabledThinking(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDisabledThinking.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicDisabledThinking(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDisabledThinking.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicDisabledThinking(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDisabledThinking.collision",
            input: """
                {
                  \"type\": \"disabled\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try AnthropicDisabledThinking(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
