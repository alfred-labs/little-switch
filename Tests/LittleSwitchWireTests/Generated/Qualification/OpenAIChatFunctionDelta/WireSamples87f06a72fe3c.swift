// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk.Choice.Delta.ToolCall.Function
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples87f06a72fe3c {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatFunctionDelta.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFunctionDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionDelta.full",
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
            return try OpenAIChatFunctionDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatFunctionDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionDelta.null:arguments",
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
            return try OpenAIChatFunctionDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionDelta.null:name",
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
            expectedError: nil
        ) { json in
            return try OpenAIChatFunctionDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionDelta.null:namespace",
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
            return try OpenAIChatFunctionDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionDelta.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["arguments"])
        ) { json in
            var value = try OpenAIChatFunctionDelta(wireJSON: json)
            value.additionalFields["arguments"] = .null
            return try value.wireJSON()
        },
    ]
}
