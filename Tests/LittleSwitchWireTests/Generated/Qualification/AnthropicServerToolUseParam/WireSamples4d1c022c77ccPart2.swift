// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ServerToolUseBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4d1c022c77ccPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerToolUseParam.missing:type",
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
                  \"name\": \"web_search\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.null:type",
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
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicServerToolUseParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUseParam.collision",
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
            expectedError: .init(.additionalFieldCollision, path: ["id"])
        ) { json in
            var value = try AnthropicServerToolUseParam(wireJSON: json)
            value.additionalFields["id"] = .null
            return try value.wireJSON()
        },
    ]
}
