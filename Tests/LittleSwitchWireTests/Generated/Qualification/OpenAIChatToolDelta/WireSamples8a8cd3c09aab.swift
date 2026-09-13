// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk.Choice.Delta.ToolCall
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8a8cd3c09aab {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatToolDelta.minimal",
            input: """
                {
                  \"index\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {},
                  \"function\": {},
                  \"id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": \"function\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.null:custom",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": null,
                  \"function\": {},
                  \"id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["custom"])
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.null:function",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {},
                  \"function\": null,
                  \"id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["function"])
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {},
                  \"function\": {},
                  \"id\": null,
                  \"index\": 1e400,
                  \"type\": \"function\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.missing:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {},
                  \"function\": {},
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.missingField, path: ["index"])
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.null:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {},
                  \"function\": {},
                  \"id\": \"wire sample\",
                  \"index\": null,
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["index"])
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {},
                  \"function\": {},
                  \"id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatToolDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatToolDelta.collision",
            input: """
                {
                  \"index\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["custom"])
        ) { json in
            var value = try OpenAIChatToolDelta(wireJSON: json)
            value.additionalFields["custom"] = .null
            return try value.wireJSON()
        },
    ]
}
