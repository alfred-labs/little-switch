// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationsWebSearchResultLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples83ac41fa3609Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebCitation.missing:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["url"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.null:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["url"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.collision",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["cited_text"])
        ) { json in
            var value = try AnthropicWebCitation(wireJSON: json)
            value.additionalFields["cited_text"] = .null
            return try value.wireJSON()
        },
    ]
}
