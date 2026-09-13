// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/CompletionUsage.PromptTokensDetails
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples907a04f18fd2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatBufferedPromptDetails.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedPromptDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedPromptDetails.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_write_tokens\": 1e400,
                  \"cached_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedPromptDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedPromptDetails.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatBufferedPromptDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedPromptDetails.null:cache_write_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_write_tokens\": null,
                  \"cached_tokens\": 1e400
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["cache_write_tokens"])
        ) { json in
            return try OpenAIChatBufferedPromptDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedPromptDetails.null:cached_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_write_tokens\": 1e400,
                  \"cached_tokens\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["cached_tokens"])
        ) { json in
            return try OpenAIChatBufferedPromptDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedPromptDetails.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["cache_write_tokens"])
        ) { json in
            var value = try OpenAIChatBufferedPromptDetails(wireJSON: json)
            value.additionalFields["cache_write_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
