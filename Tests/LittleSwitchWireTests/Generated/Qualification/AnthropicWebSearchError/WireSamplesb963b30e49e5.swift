// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/WebSearchToolResultError
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb963b30e49e5 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchError.minimal",
            input: """
                {
                  \"error_code\": \"invalid_tool_input\",
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"error_code\": \"invalid_tool_input\",
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.missing:error_code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: .init(.missingField, path: ["error_code"])
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.null:error_code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"error_code\": null,
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["error_code"])
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"error_code\": \"invalid_tool_input\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"error_code\": \"invalid_tool_input\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicWebSearchError(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchError.collision",
            input: """
                {
                  \"error_code\": \"invalid_tool_input\",
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["error_code"])
        ) { json in
            var value = try AnthropicWebSearchError(wireJSON: json)
            value.additionalFields["error_code"] = .null
            return try value.wireJSON()
        },
    ]
}
