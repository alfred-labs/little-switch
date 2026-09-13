// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ToolChoiceAuto
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 5ed50fff4afe63e02ee97dc411bd9fc6b942991e1028c9ce4aa20194b8e0722c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7356e68fcdf0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicAutomaticToolChoice.minimal",
            input: """
                {
                  \"type\": \"auto\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicAutomaticToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicAutomaticToolChoice.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"auto\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicAutomaticToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicAutomaticToolChoice.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicAutomaticToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicAutomaticToolChoice.missing:type",
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
            return try AnthropicAutomaticToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicAutomaticToolChoice.null:type",
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
            return try AnthropicAutomaticToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicAutomaticToolChoice.collision",
            input: """
                {
                  \"type\": \"auto\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try AnthropicAutomaticToolChoice(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
