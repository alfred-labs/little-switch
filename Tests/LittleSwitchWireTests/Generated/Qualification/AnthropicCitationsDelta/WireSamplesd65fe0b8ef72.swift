// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/CitationsDelta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd65fe0b8ef72 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCitationsDelta.minimal",
            input: """
                {
                  \"type\": \"citations_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationsDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try AnthropicCitationsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationsDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicCitationsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationsDelta.null:citation",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citation\": null,
                  \"type\": \"citations_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCitationsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationsDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicCitationsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationsDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicCitationsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCitationsDelta.collision",
            input: """
                {
                  \"type\": \"citations_delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["citation"])
        ) { json in
            var value = try AnthropicCitationsDelta(wireJSON: json)
            value.additionalFields["citation"] = .null
            return try value.wireJSON()
        },
    ]
}
