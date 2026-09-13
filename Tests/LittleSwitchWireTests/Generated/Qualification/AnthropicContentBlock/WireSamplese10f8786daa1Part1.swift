// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ContentBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese10f8786daa1Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlock.branch:0",
            input: """
                {
                  \"citations\": [],
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.malformed-branch:0",
            input: """
                {
                  \"citations\": [],
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.branch:1",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.malformed-branch:1",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.missingField, path: ["thinking"])
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.branch:2",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.malformed-branch:2",
            input: """
                {
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: .init(.missingField, path: ["data"])
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.branch:3",
            input: """
                {
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
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.malformed-branch:3",
            input: """
                {
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
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.branch:4",
            input: """
                {
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
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.malformed-branch:4",
            input: """
                {
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
                  \"name\": \"web_search\",
                  \"type\": \"server_tool_use\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.branch:5",
            input: """
                {
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
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
    ]
}
