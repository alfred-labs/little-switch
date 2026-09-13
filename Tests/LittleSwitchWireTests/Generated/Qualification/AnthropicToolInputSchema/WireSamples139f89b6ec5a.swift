// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/Tool.InputSchema
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 74783645dc5631624eea4f074e76df445c891d52e9ccacc4c2107e70733cf7fc
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples139f89b6ec5a {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolInputSchema.minimal",
            input: """
                {
                  \"type\": \"object\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"properties\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"required\": [],
                  \"type\": \"object\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.null:properties",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"properties\": null,
                  \"required\": [],
                  \"type\": \"object\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.null:required",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"properties\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"required\": null,
                  \"type\": \"object\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"properties\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"required\": []
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"properties\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"required\": [],
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicToolInputSchema(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolInputSchema.collision",
            input: """
                {
                  \"type\": \"object\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["properties"])
        ) { json in
            var value = try AnthropicToolInputSchema(wireJSON: json)
            value.additionalFields["properties"] = .null
            return try value.wireJSON()
        },
    ]
}
