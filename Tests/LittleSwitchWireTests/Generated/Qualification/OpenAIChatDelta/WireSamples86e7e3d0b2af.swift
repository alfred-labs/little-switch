// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk.Choice.Delta
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples86e7e3d0b2af {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatDelta.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": \"wire sample\",
                  \"role\": \"developer\",
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"refusal\": \"wire sample\",
                  \"role\": \"developer\",
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.null:refusal",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": null,
                  \"role\": \"developer\",
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.null:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": \"wire sample\",
                  \"role\": null,
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.null:tool_calls",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": \"wire sample\",
                  \"role\": \"developer\",
                  \"tool_calls\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatDelta.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIChatDelta(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
