// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ToolResultBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5fff371b16f1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolResultParam.minimal",
            input: """
                {
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.full",
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
                  \"is_error\": true,
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"is_error\": true,
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.null:is_error",
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
                  \"is_error\": null,
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["is_error"])
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.missing:tool_use_id",
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
                  \"is_error\": true,
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_use_id"])
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.null:tool_use_id",
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
                  \"is_error\": true,
                  \"tool_use_id\": null,
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_use_id"])
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.missing:type",
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
                  \"is_error\": true,
                  \"tool_use_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.null:type",
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
                  \"is_error\": true,
                  \"tool_use_id\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicToolResultParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParam.collision",
            input: """
                {
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"tool_result\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try AnthropicToolResultParam(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
