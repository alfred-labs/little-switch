// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolUsage
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: d81fbd6e0d8394b127f943788bdaf2ad26bc34bfa41b5b46d17d6c4ba7c6a8fb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples68e645b48364 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerToolUsage.minimal",
            input: """
                {
                  \"web_fetch_requests\": 9007199254740993,
                  \"web_search_requests\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"web_fetch_requests\": 1e400,
                  \"web_search_requests\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.missing:web_fetch_requests",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"web_search_requests\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["web_fetch_requests"])
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.null:web_fetch_requests",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"web_fetch_requests\": null,
                  \"web_search_requests\": 1e400
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["web_fetch_requests"])
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.missing:web_search_requests",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"web_fetch_requests\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["web_search_requests"])
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.null:web_search_requests",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"web_fetch_requests\": 1e400,
                  \"web_search_requests\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["web_search_requests"])
        ) { json in
            return try AnthropicServerToolUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolUsage.collision",
            input: """
                {
                  \"web_fetch_requests\": 9007199254740993,
                  \"web_search_requests\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["web_fetch_requests"])
        ) { json in
            var value = try AnthropicServerToolUsage(wireJSON: json)
            value.additionalFields["web_fetch_requests"] = .null
            return try value.wireJSON()
        },
    ]
}
