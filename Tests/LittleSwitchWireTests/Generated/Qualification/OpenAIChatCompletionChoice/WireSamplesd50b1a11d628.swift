// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletion.Choice
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd50b1a11d628 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCompletionChoice.minimal",
            input: """
                {
                  \"finish_reason\": \"stop\",
                  \"message\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"finish_reason\": \"stop\",
                  \"message\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.missing:finish_reason",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": {}
                }
                """,
            expectedError: .init(.missingField, path: ["finish_reason"])
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.null:finish_reason",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"finish_reason\": null,
                  \"message\": {}
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["finish_reason"])
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.missing:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"finish_reason\": \"stop\"
                }
                """,
            expectedError: .init(.missingField, path: ["message"])
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.null:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"finish_reason\": \"stop\",
                  \"message\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["message"])
        ) { json in
            return try OpenAIChatCompletionChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionChoice.collision",
            input: """
                {
                  \"finish_reason\": \"stop\",
                  \"message\": {}
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["finish_reason"])
        ) { json in
            var value = try OpenAIChatCompletionChoice(wireJSON: json)
            value.additionalFields["finish_reason"] = .null
            return try value.wireJSON()
        },
    ]
}
