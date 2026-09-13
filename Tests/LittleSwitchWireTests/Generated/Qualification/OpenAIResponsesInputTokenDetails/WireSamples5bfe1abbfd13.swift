// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseUsage.InputTokensDetails
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5bfe1abbfd13 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputTokenDetails.minimal",
            input: """
                {
                  \"cached_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTokenDetails.full",
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
            return try OpenAIResponsesInputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTokenDetails.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesInputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTokenDetails.null:cache_write_tokens",
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
            return try OpenAIResponsesInputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTokenDetails.missing:cached_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_write_tokens\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["cached_tokens"])
        ) { json in
            return try OpenAIResponsesInputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTokenDetails.null:cached_tokens",
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
            return try OpenAIResponsesInputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTokenDetails.collision",
            input: """
                {
                  \"cached_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["cache_write_tokens"])
        ) { json in
            var value = try OpenAIResponsesInputTokenDetails(wireJSON: json)
            value.additionalFields["cache_write_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
