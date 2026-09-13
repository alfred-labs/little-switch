// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessageFunctionToolCall.Function
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese4bf65806d60 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatFunctionInput.minimal",
            input: """
                {
                  \"arguments\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.missing:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["arguments"])
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.null:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": null,
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["arguments"])
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"name\": null,
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.null:namespace",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFunctionInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionInput.collision",
            input: """
                {
                  \"arguments\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["arguments"])
        ) { json in
            var value = try OpenAIChatFunctionInput(wireJSON: json)
            value.additionalFields["arguments"] = .null
            return try value.wireJSON()
        },
    ]
}
