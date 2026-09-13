// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionToolMessageParam
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9f4f8f1d3e15 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestTool.minimal",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.full",
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
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.missing:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.missing:role",
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
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.null:role",
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
                  \"role\": null,
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["role"])
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.missing:tool_call_id",
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
                  \"role\": \"tool\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_call_id"])
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.null:tool_call_id",
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
                  \"role\": \"tool\",
                  \"tool_call_id\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_call_id"])
        ) { json in
            return try OpenAIChatRequestTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestTool.collision",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIChatRequestTool(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
