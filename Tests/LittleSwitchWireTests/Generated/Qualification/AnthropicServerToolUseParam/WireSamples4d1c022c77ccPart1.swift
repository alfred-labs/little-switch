// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ServerToolUseBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4d1c022c77ccPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerToolUseParam.minimal",
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
            expectedError: nil
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
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
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"web_search\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
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
                  \"name\": \"web_search\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.missing:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"name\": \"web_search\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.null:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"input\": null,
                  \"name\": \"web_search\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
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
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
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
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.open:name",
            input: """
                {
                  \"__wire_unknown__\": {
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
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
    ]
}
