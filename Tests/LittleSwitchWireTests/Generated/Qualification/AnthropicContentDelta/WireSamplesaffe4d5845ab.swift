// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawContentBlockDelta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesaffe4d5845ab {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentDelta.branch:0",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.malformed-branch:0",
            input: """
                {
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.branch:1",
            input: """
                {
                  \"partial_json\": \"wire sample\",
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.malformed-branch:1",
            input: """
                {
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["partial_json"])
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.branch:2",
            input: """
                {
                  \"citation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"citations_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.branch:3",
            input: """
                {
                  \"thinking\": \"wire sample\",
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.malformed-branch:3",
            input: """
                {
                  \"type\": \"thinking_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["thinking"])
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.branch:4",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.malformed-branch:4",
            input: """
                {
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["signature"])
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.unknown",
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
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.unknown-mismatch",
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
            return try AnthropicContentDelta.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicContentDelta.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentDelta(wireJSON: json).wireJSON()
        },
    ]
}
