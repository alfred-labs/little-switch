// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Usage
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: d81fbd6e0d8394b127f943788bdaf2ad26bc34bfa41b5b46d17d6c4ba7c6a8fb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf55d201e6674 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicPublicUsage.minimal",
            input: """
                {
                  \"server_tool_use\": {
                    \"web_fetch_requests\": 9007199254740993,
                    \"web_search_requests\": 9007199254740993
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPublicUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicUsage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"server_tool_use\": {
                    \"web_fetch_requests\": 9007199254740993,
                    \"web_search_requests\": 9007199254740993
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPublicUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicUsage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicPublicUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicUsage.missing:server_tool_use",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["server_tool_use"])
        ) { json in
            return try AnthropicPublicUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicUsage.null:server_tool_use",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"server_tool_use\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPublicUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicUsage.collision",
            input: """
                {
                  \"server_tool_use\": {
                    \"web_fetch_requests\": 9007199254740993,
                    \"web_search_requests\": 9007199254740993
                  }
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["server_tool_use"])
        ) { json in
            var value = try AnthropicPublicUsage(wireJSON: json)
            value.additionalFields["server_tool_use"] = .null
            return try value.wireJSON()
        },
    ]
}
