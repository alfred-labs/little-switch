// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk.Choice.Delta.ToolCall.Custom
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4fc367c58f3b {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCustomDelta.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomDelta.full",
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
            return try OpenAIChatCustomDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatCustomDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomDelta.null:input",
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
            return try OpenAIChatCustomDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomDelta.null:name",
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
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomDelta.null:namespace",
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
            return try OpenAIChatCustomDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomDelta.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input"])
        ) { json in
            var value = try OpenAIChatCustomDelta(wireJSON: json)
            value.additionalFields["input"] = .null
            return try value.wireJSON()
        },
    ]
}
