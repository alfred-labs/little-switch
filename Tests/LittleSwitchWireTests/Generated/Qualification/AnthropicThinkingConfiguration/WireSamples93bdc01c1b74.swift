// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ThinkingConfigParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: fec4acfe2c5e4e5e6da8e260eae299ff0b3652ffcec38e650f98234cfeb9699b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples93bdc01c1b74 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicThinkingConfiguration.branch:0",
            input: """
                {
                  \"type\": \"disabled\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingConfiguration.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingConfiguration.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicThinkingConfiguration.unknown(type: "__wire_unknown___mismatch", payload: json)
                .wireJSON()
        },
        .init(
            name: "AnthropicThinkingConfiguration.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicThinkingConfiguration(wireJSON: json).wireJSON()
        },
    ]
}
