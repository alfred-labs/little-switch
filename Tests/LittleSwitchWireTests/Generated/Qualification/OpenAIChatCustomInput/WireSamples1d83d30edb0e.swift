// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessageCustomToolCall.Custom
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1d83d30edb0e {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCustomInput.minimal",
            input: """
                {
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.missing:input",
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
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.null:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": null,
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["input"])
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\",
                  \"name\": null,
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.null:namespace",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomInput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomInput.collision",
            input: """
                {
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input"])
        ) { json in
            var value = try OpenAIChatCustomInput(wireJSON: json)
            value.additionalFields["input"] = .null
            return try value.wireJSON()
        },
    ]
}
