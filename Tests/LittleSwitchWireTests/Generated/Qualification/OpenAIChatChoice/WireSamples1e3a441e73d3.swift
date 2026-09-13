// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk.Choice
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1e3a441e73d3 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatChoice.minimal",
            input: """
                {
                  \"delta\": {},
                  \"index\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {},
                  \"finish_reason\": \"stop\",
                  \"index\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.missing:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"finish_reason\": \"stop\",
                  \"index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.null:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": null,
                  \"finish_reason\": \"stop\",
                  \"index\": 1e400
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["delta"])
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.null:finish_reason",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {},
                  \"finish_reason\": null,
                  \"index\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.missing:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {},
                  \"finish_reason\": \"stop\"
                }
                """,
            expectedError: .init(.missingField, path: ["index"])
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.null:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {},
                  \"finish_reason\": \"stop\",
                  \"index\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["index"])
        ) { json in
            return try OpenAIChatChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChoice.collision",
            input: """
                {
                  \"delta\": {},
                  \"index\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["delta"])
        ) { json in
            var value = try OpenAIChatChoice(wireJSON: json)
            value.additionalFields["delta"] = .null
            return try value.wireJSON()
        },
    ]
}
