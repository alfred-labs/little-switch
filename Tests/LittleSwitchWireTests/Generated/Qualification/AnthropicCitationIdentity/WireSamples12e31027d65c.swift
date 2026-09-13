// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/TextCitation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: aadc98429ee542042a3d6a5fc24b7f9620494666786e9eff65ba249bf7174a3b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples12e31027d65c {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCitationIdentity.branch:0",
            input: """
                {
                  \"type\": \"char_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.branch:1",
            input: """
                {
                  \"type\": \"page_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.branch:2",
            input: """
                {
                  \"type\": \"content_block_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.branch:3",
            input: """
                {
                  \"type\": \"web_search_result_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.branch:4",
            input: """
                {
                  \"type\": \"search_result_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.unknown",
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
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.unknown-mismatch",
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
            return try AnthropicCitationIdentity.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationIdentity.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicCitationIdentity(wireJSON: json).wireJSON()
        },
    ]
}
