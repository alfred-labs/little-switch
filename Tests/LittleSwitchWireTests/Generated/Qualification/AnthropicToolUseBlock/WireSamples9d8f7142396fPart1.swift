// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ToolUseBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9d8f7142396fPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolUseBlock.minimal",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.null:caller",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": null,
                  \"id\": \"wire sample\",
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": null,
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.missing:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlock.null:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"input\": null,
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolUseBlock(wireJSON: json).wireJSON()
        },
    ]
}
