// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessageFunctionToolCall
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9c49f78ed7ac {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatFunctionCall.minimal",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.full",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.missing:function",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.null:function",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.missing:id",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.null:id",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.missing:type",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.null:type",
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
            return try OpenAIChatFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCall.collision",
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
            var value = try OpenAIChatFunctionCall(wireJSON: json)
            value.additionalFields["function"] = .null
            return try value.wireJSON()
        },
    ]
}
