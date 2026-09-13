// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationContentBlockLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: aadc98429ee542042a3d6a5fc24b7f9620494666786e9eff65ba249bf7174a3b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa4c1ed016ac2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentCitationIdentity.minimal",
            input: """
                {
                  \"type\": \"content_block_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentCitationIdentity.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"content_block_location\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentCitationIdentity.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicContentCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentCitationIdentity.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentCitationIdentity.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicContentCitationIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentCitationIdentity.collision",
            input: """
                {
                  \"type\": \"content_block_location\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try AnthropicContentCitationIdentity(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
