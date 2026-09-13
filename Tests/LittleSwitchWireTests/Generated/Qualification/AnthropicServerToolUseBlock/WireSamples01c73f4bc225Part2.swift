// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolUseBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples01c73f4bc225Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerToolUseBlock.missing:name",
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
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try AnthropicServerToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseBlock.null:name",
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
                  \"name\": null,
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try AnthropicServerToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseBlock.open:name",
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
                  \"name\": \"__wire_future_value__\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseBlock.missing:type",
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
                  \"name\": \"web_search\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicServerToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseBlock.null:type",
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
                  \"name\": \"web_search\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicServerToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseBlock.collision",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"web_search\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["caller"])
        ) { json in
            var value = try AnthropicServerToolUseBlock(wireJSON: json)
            value.additionalFields["caller"] = .null
            return try value.wireJSON()
        },
    ]
}
