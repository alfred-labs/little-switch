// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationPageLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc1b89e0128b1Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicPageCitation.null:file_id",
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
                  \"file_id\": null,
                  \"start_page_number\": 1e400,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.missing:start_page_number",
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
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.missingField, path: ["start_page_number"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.null:start_page_number",
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
                  \"start_page_number\": null,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["start_page_number"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.missing:type",
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
                  \"start_page_number\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.null:type",
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
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicPageCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPageCitation.collision",
            input: """
                {
                  \"cited_text\": \"wire sample\",
                  \"document_index\": 9007199254740993,
                  \"end_page_number\": 9007199254740993,
                  \"start_page_number\": 9007199254740993,
                  \"type\": \"page_location\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["cited_text"])
        ) { json in
            var value = try AnthropicPageCitation(wireJSON: json)
            value.additionalFields["cited_text"] = .null
            return try value.wireJSON()
        },
    ]
}
