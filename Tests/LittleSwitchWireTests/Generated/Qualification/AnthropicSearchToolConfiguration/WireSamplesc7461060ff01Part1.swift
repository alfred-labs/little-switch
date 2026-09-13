// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/WebSearchTool20250305
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: cb662fa62dc86582eeda7ba693d5a7b28cc3517c2496c67a1ce665a81b793aa2
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc7461060ff01Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSearchToolConfiguration.minimal",
            input: """
                {
                  \"name\": \"web_search\",
                  \"type\": \"web_search_20250305\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": [
                    \"direct\"
                  ],
                  \"allowed_domains\": [],
                  \"blocked_domains\": [],
                  \"max_uses\": 9007199254740993,
                  \"name\": \"web_search\",
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.null:allowed_callers",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": null,
                  \"allowed_domains\": [],
                  \"blocked_domains\": [],
                  \"max_uses\": 9007199254740993,
                  \"name\": \"web_search\",
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["allowed_callers"])
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.null:allowed_domains",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": [
                    \"direct\"
                  ],
                  \"allowed_domains\": null,
                  \"blocked_domains\": [],
                  \"max_uses\": 9007199254740993,
                  \"name\": \"web_search\",
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.null:blocked_domains",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": [
                    \"direct\"
                  ],
                  \"allowed_domains\": [],
                  \"blocked_domains\": null,
                  \"max_uses\": 9007199254740993,
                  \"name\": \"web_search\",
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.null:max_uses",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": [
                    \"direct\"
                  ],
                  \"allowed_domains\": [],
                  \"blocked_domains\": [],
                  \"max_uses\": null,
                  \"name\": \"web_search\",
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": [
                    \"direct\"
                  ],
                  \"allowed_domains\": [],
                  \"blocked_domains\": [],
                  \"max_uses\": 9007199254740993,
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchToolConfiguration.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"allowed_callers\": [
                    \"direct\"
                  ],
                  \"allowed_domains\": [],
                  \"blocked_domains\": [],
                  \"max_uses\": 9007199254740993,
                  \"name\": null,
                  \"type\": \"web_search_20250305\",
                  \"user_location\": {
                    \"type\": \"approximate\"
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try AnthropicSearchToolConfiguration(wireJSON: json).wireJSON()
        },
    ]
}
