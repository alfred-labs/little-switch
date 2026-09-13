// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/CompletionUsage
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0cb5123d0f19 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatStreamUsage.minimal",
            input: """
                {
                  \"completion_tokens\": 9007199254740993,
                  \"prompt_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.missing:completion_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.missingField, path: ["completion_tokens"])
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.null:completion_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": null,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["completion_tokens"])
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.null:completion_tokens_details",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": null,
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.missing:prompt_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.missingField, path: ["prompt_tokens"])
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.null:prompt_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": null,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["prompt_tokens"])
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.null:prompt_tokens_details",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": null,
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.null:total_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatStreamUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatStreamUsage.collision",
            input: """
                {
                  \"completion_tokens\": 9007199254740993,
                  \"prompt_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["completion_tokens"])
        ) { json in
            var value = try OpenAIChatStreamUsage(wireJSON: json)
            value.additionalFields["completion_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
