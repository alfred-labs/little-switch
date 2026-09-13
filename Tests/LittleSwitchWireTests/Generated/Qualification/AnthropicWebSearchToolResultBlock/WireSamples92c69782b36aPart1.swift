// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/WebSearchToolResultBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples92c69782b36aPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchToolResultBlock.minimal",
            input: """
                {
                  \"content\": {
                    \"error_code\": \"invalid_tool_input\",
                    \"type\": \"web_search_tool_result_error\"
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.full",
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
                  \"content\": {
                    \"error_code\": \"invalid_tool_input\",
                    \"type\": \"web_search_tool_result_error\"
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.null:caller",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"caller\": null,
                  \"content\": {
                    \"error_code\": \"invalid_tool_input\",
                    \"type\": \"web_search_tool_result_error\"
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.missing:content",
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
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.null:content",
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
                  \"content\": null,
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content"])
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.missing:tool_use_id",
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
                  \"content\": {
                    \"error_code\": \"invalid_tool_input\",
                    \"type\": \"web_search_tool_result_error\"
                  },
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_use_id"])
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.null:tool_use_id",
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
                  \"content\": {
                    \"error_code\": \"invalid_tool_input\",
                    \"type\": \"web_search_tool_result_error\"
                  },
                  \"tool_use_id\": null,
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_use_id"])
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchToolResultBlock.missing:type",
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
                  \"content\": {
                    \"error_code\": \"invalid_tool_input\",
                    \"type\": \"web_search_tool_result_error\"
                  },
                  \"tool_use_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicWebSearchToolResultBlock(wireJSON: json).wireJSON()
        },
    ]
}
