// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9fbc8d89f7dbPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatChunk.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"delta\": {},
                      \"index\": 9007199254740993
                    }
                  ],
                  \"created\": 1e400,
                  \"id\": null,
                  \"model\": \"wire sample\",
                  \"object\": \"chat.completion.chunk\",
                  \"usage\": {
                    \"completion_tokens\": 9007199254740993,
                    \"prompt_tokens\": 9007199254740993
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIChatChunk(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunk.missing:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"delta\": {},
                      \"index\": 9007199254740993
                    }
                  ],
                  \"created\": 1e400,
                  \"id\": \"wire sample\",
                  \"object\": \"chat.completion.chunk\",
                  \"usage\": {
                    \"completion_tokens\": 9007199254740993,
                    \"prompt_tokens\": 9007199254740993
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["model"])
        ) { json in
            return try OpenAIChatChunk(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunk.null:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"delta\": {},
                      \"index\": 9007199254740993
                    }
                  ],
                  \"created\": 1e400,
                  \"id\": \"wire sample\",
                  \"model\": null,
                  \"object\": \"chat.completion.chunk\",
                  \"usage\": {
                    \"completion_tokens\": 9007199254740993,
                    \"prompt_tokens\": 9007199254740993
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["model"])
        ) { json in
            return try OpenAIChatChunk(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunk.missing:object",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"delta\": {},
                      \"index\": 9007199254740993
                    }
                  ],
                  \"created\": 1e400,
                  \"id\": \"wire sample\",
                  \"model\": \"wire sample\",
                  \"usage\": {
                    \"completion_tokens\": 9007199254740993,
                    \"prompt_tokens\": 9007199254740993
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["object"])
        ) { json in
            return try OpenAIChatChunk(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunk.null:object",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"delta\": {},
                      \"index\": 9007199254740993
                    }
                  ],
                  \"created\": 1e400,
                  \"id\": \"wire sample\",
                  \"model\": \"wire sample\",
                  \"object\": null,
                  \"usage\": {
                    \"completion_tokens\": 9007199254740993,
                    \"prompt_tokens\": 9007199254740993
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["object"])
        ) { json in
            return try OpenAIChatChunk(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunk.null:usage",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"delta\": {},
                      \"index\": 9007199254740993
                    }
                  ],
                  \"created\": 1e400,
                  \"id\": \"wire sample\",
                  \"model\": \"wire sample\",
                  \"object\": \"chat.completion.chunk\",
                  \"usage\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatChunk(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatChunk.collision",
            input: """
                {
                  \"choices\": [],
                  \"created\": 9007199254740993,
                  \"id\": \"wire sample\",
                  \"model\": \"wire sample\",
                  \"object\": \"chat.completion.chunk\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["choices"])
        ) { json in
            var value = try OpenAIChatChunk(wireJSON: json)
            value.additionalFields["choices"] = .null
            return try value.wireJSON()
        },
    ]
}
