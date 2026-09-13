// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ContentBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese10f8786daa1Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlock.malformed-branch:5",
            input: """
                {
                  \"caller\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_use_id\": \"wire sample\",
                  \"type\": \"web_search_tool_result\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.unknown",
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
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.unknown-mismatch",
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
            return try AnthropicContentBlock.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlock.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentBlock(wireJSON: json).wireJSON()
        },
    ]
}
