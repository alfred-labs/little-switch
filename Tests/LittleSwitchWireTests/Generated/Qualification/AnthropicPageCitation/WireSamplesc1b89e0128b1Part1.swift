// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationPageLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc1b89e0128b1Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicPageCitation.minimal",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 9007199254740993,
                  \"end_page_number\": 9007199254740993,
                  \"start_page_number\": 9007199254740993,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.missing:cited_text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.null:cited_text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": null,
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_page_number\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["cited_text"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.missing:document_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"document_title\": \"wire sample\",
                  \"end_page_number\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["document_index"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.null:document_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"document_index\": null,
                  \"document_title\": \"wire sample\",
                  \"end_page_number\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["document_index"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.null:document_title",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 1e400,
                  \"document_title\": null,
                  \"end_page_number\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.missing:end_page_number",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["end_page_number"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.null:end_page_number",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 1e400,
                  \"document_title\": \"wire sample\",
                  \"end_page_number\": null,
                  \"file_id\": \"wire sample\",
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["end_page_number"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
    ]
}
