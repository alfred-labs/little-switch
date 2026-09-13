// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationsSearchResultLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc409f57ee258Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSearchCitation.null:source",
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
                  \"source\": null,
                  \"start_block_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["source"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.missing:start_block_index",
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
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["start_block_index"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.null:start_block_index",
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
                  \"start_block_index\": null,
                  \"title\": \"wire sample\",
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["start_block_index"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.null:title",
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
                  \"title\": null,
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.missing:type",
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
                  \"title\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.null:type",
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
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicSearchCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitation.collision",
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
            expectedError: .init(.additionalFieldCollision, path: ["cited_text"])
        ) { json in
            var value = try AnthropicSearchCitation(wireJSON: json)
            value.additionalFields["cited_text"] = .null
            return try value.wireJSON()
        },
    ]
}
