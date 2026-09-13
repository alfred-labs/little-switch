// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ContentBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples68610422c7faPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlockParam.branch:7",
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:7",
            input: """
                {
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:8",
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:8",
            input: """
                {
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicContentBlockParam.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
    ]
}
