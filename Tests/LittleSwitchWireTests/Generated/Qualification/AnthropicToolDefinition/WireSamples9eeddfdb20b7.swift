// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/Tool
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 74783645dc5631624eea4f074e76df445c891d52e9ccacc4c2107e70733cf7fc
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9eeddfdb20b7 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolDefinition.minimal",
            input: """
                {
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": \"wire sample\",
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.null:description",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": null,
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["description"])
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.missing:input_schema",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.missingField, path: ["input_schema"])
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.null:input_schema",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": \"wire sample\",
                  \"input_schema\": null,
                  \"name\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["input_schema"])
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": \"wire sample\",
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": \"wire sample\",
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"name\": null,
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"description\": \"wire sample\",
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"name\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolDefinition(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinition.collision",
            input: """
                {
                  \"input_schema\": {
                    \"type\": \"object\"
                  },
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["description"])
        ) { json in
            var value = try AnthropicToolDefinition(wireJSON: json)
            value.additionalFields["description"] = .null
            return try value.wireJSON()
        },
    ]
}
