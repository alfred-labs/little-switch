// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/WebSearchToolResultBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples59b2b669eca4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchResultParam.minimal",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.missing:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.missing:tool_use_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_use_id"])
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.null:tool_use_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": null,
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_use_id"])
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicWebSearchResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResultParam.collision",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try AnthropicWebSearchResultParam(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
