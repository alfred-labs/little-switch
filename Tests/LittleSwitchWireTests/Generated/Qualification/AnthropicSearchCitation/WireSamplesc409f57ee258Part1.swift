// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationsSearchResultLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc409f57ee258Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSearchCitation.minimal",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"end_block_index\": 9007199254740993,
                  \"search_result_index\": 9007199254740993,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 9007199254740993,
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"end_block_index\": 1e400,
                  \"search_result_index\": 1e400,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.missing:cited_text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"end_block_index\": 1e400,
                  \"search_result_index\": 1e400,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["cited_text"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.null:cited_text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": null,
                  \"end_block_index\": 1e400,
                  \"search_result_index\": 1e400,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["cited_text"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.missing:end_block_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"search_result_index\": 1e400,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["end_block_index"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.null:end_block_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"end_block_index\": null,
                  \"search_result_index\": 1e400,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["end_block_index"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.missing:search_result_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"end_block_index\": 1e400,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["search_result_index"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.null:search_result_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"end_block_index\": 1e400,
                  \"search_result_index\": null,
                  \"source\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["search_result_index"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.missing:source",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"end_block_index\": 1e400,
                  \"search_result_index\": 1e400,
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["source"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
    ]
}
