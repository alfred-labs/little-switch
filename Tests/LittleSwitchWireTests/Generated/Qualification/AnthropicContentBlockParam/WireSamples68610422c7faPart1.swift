// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ContentBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples68610422c7faPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlockParam.branch:0",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:0",
            input: """
                {
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:1",
            input: """
                {
                  \"source\": {
                    \"data\": \"wire sample\",
                    \"media_type\": \"image/jpeg\",
                    \"type\": \"base64\"
                  },
                  \"type\": \"image\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:1",
            input: """
                {
                  \"type\": \"image\"
                }
                """,
            expectedError: .init(.missingField, path: ["source"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:2",
            input: """
                {
                  \"source\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"document\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:2",
            input: """
                {
                  \"type\": \"document\"
                }
                """,
            expectedError: .init(.missingField, path: ["source"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:3",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:3",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"type\": \"thinking\"
                }
                """,
            expectedError: .init(.missingField, path: ["thinking"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:4",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:4",
            input: """
                {
                  \"type\": \"redacted_thinking\"
                }
                """,
            expectedError: .init(.missingField, path: ["data"])
        ) { json in
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:5",
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:5",
            input: """
                {
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.branch:6",
            input: """
                {
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockParam.malformed-branch:6",
            input: """
                {
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
            return try AnthropicContentBlockParam(wireJSON: json).wireJSON()
        },
    ]
}
