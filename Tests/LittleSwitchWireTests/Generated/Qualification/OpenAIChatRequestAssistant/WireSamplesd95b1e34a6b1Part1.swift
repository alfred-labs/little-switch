// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionAssistantMessageParam
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd95b1e34a6b1Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestAssistant.minimal",
            input: """
                {
                  \"role\": \"assistant\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.full",
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
                  \"refusal\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"tool_calls\": [
                    {
                      \"function\": {
                        \"arguments\": \"wire sample\",
                        \"name\": \"wire sample\"
                      },
                      \"id\": \"wire sample\",
                      \"type\": \"function\"
                    }
                  ]
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"refusal\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"tool_calls\": [
                    {
                      \"function\": {
                        \"arguments\": \"wire sample\",
                        \"name\": \"wire sample\"
                      },
                      \"id\": \"wire sample\",
                      \"type\": \"function\"
                    }
                  ]
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.null:refusal",
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
                  \"refusal\": null,
                  \"role\": \"assistant\",
                  \"tool_calls\": [
                    {
                      \"function\": {
                        \"arguments\": \"wire sample\",
                        \"name\": \"wire sample\"
                      },
                      \"id\": \"wire sample\",
                      \"type\": \"function\"
                    }
                  ]
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.missing:role",
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
                  \"refusal\": \"wire sample\",
                  \"tool_calls\": [
                    {
                      \"function\": {
                        \"arguments\": \"wire sample\",
                        \"name\": \"wire sample\"
                      },
                      \"id\": \"wire sample\",
                      \"type\": \"function\"
                    }
                  ]
                }
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.null:role",
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
                  \"refusal\": \"wire sample\",
                  \"role\": null,
                  \"tool_calls\": [
                    {
                      \"function\": {
                        \"arguments\": \"wire sample\",
                        \"name\": \"wire sample\"
                      },
                      \"id\": \"wire sample\",
                      \"type\": \"function\"
                    }
                  ]
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["role"])
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistant.null:tool_calls",
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
                  \"refusal\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"tool_calls\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_calls"])
        ) { json in
            return try OpenAIChatRequestAssistant(wireJSON: json).wireJSON()
        },
    ]
}
