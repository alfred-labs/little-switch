// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionMessageFunctionToolCall
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4d6e2e1b88cb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestFunctionCall.minimal",
            input: """
                {
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.missing:function",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.missingField, path: ["function"])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.null:function",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"function\": null,
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["function"])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": null,
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIChatRequestFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCall.collision",
            input: """
                {
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["function"])
        ) { json in
            var value = try OpenAIChatRequestFunctionCall(wireJSON: json)
            value.additionalFields["function"] = .null
            return try value.wireJSON()
        },
    ]
}
