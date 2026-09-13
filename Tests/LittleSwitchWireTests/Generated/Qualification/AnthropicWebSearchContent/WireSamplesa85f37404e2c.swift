// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/WebSearchToolResultBlockContent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa85f37404e2c {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchContent.branch:0",
            input: """
                {
                  \"error_code\": \"invalid_tool_input\",
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchContent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchContent.encode-branch:0",
            input: """
                {
                  \"error_code\": \"invalid_tool_input\",
                  \"type\": \"web_search_tool_result_error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchContent.variant1(AnthropicWebSearchError(wireJSON: json)).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchContent.branch:1",
            input: """
                [
                  {
                    \"encrypted_content\": \"wire sample\",
                    \"page_age\": \"wire sample\",
                    \"title\": \"wire sample\",
                    \"type\": \"web_search_result\",
                    \"url\": \"wire sample\"
                  }
                ]
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchContent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchContent.encode-branch:1",
            input: """
                [
                  {
                    \"encrypted_content\": \"wire sample\",
                    \"page_age\": \"wire sample\",
                    \"title\": \"wire sample\",
                    \"type\": \"web_search_result\",
                    \"url\": \"wire sample\"
                  }
                ]
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchContent.variant2([AnthropicWebSearchResult](wireJSON: json)).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchContent.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicWebSearchContent(wireJSON: json).wireJSON()
        },
    ]
}
