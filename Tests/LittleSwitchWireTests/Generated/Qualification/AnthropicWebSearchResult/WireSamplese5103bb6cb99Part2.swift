// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/WebSearchResultBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese5103bb6cb99Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchResult.missing:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"page_age\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["url"])
        ) { json in
            return try AnthropicWebSearchResult(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResult.null:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"page_age\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result\",
                  \"url\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["url"])
        ) { json in
            return try AnthropicWebSearchResult(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchResult.collision",
            input: """
                {
                  \"encrypted_content\": \"wire sample\",
                  \"page_age\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["encrypted_content"])
        ) { json in
            var value = try AnthropicWebSearchResult(wireJSON: json)
            value.additionalFields["encrypted_content"] = .null
            return try value.wireJSON()
        },
    ]
}
