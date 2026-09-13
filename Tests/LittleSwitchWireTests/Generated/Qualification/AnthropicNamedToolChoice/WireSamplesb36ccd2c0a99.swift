// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ToolChoiceTool
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: e2b65972c18933bd197b440281af627830410cc632fc64aaadf7c934538cbacb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb36ccd2c0a99 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicNamedToolChoice.minimal",
            input: """
                {
                  \"name\": \"wire sample\",
                  \"type\": \"tool\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": null,
                  \"type\": \"tool\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicNamedToolChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoice.collision",
            input: """
                {
                  \"name\": \"wire sample\",
                  \"type\": \"tool\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["name"])
        ) { json in
            var value = try AnthropicNamedToolChoice(wireJSON: json)
            value.additionalFields["name"] = .null
            return try value.wireJSON()
        },
    ]
}
