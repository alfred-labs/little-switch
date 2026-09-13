// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationsWebSearchResultLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples83ac41fa3609Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebCitation.minimal",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.full",
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
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.missing:cited_text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["cited_text"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.null:cited_text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": null,
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["cited_text"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.missing:encrypted_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["encrypted_index"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.null:encrypted_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": null,
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["encrypted_index"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.missing:title",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["title"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.null:title",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"encrypted_index\": \"wire sample\",
                  \"title\": null,
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.missing:type",
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
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebCitation.null:type",
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
                  \"type\": null,
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicWebCitation(wireJSON: json).wireJSON()
        },
    ]
}
