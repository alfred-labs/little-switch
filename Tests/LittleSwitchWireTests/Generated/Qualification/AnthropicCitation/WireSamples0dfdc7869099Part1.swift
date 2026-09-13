// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/TextCitation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0dfdc7869099Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCitation.branch:0",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_char_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_char_index\": 1e400,
                  \"type\": \"char_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.malformed-branch:0",
            input: """
                {
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_char_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_char_index\": 1e400,
                  \"type\": \"char_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["cited_text"])
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.branch:1",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_page_number\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.malformed-branch:1",
            input: """
                {
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_page_number\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["cited_text"])
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.branch:2",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_block_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"type\": \"content_block_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.malformed-branch:2",
            input: """
                {
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_block_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_block_index\": 1e400,
                  \"type\": \"content_block_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["cited_text"])
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.branch:3",
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
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.malformed-branch:3",
            input: """
                {
                  \"encrypted_index\": \"wire sample\",
                  \"title\": \"wire sample\",
                  \"type\": \"web_search_result_location\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["cited_text"])
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.branch:4",
            input: """
                {
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
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.malformed-branch:4",
            input: """
                {
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
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitation.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicCitation.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
    ]
}
