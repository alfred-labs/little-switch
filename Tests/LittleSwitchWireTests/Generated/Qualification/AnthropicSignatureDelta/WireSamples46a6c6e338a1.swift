// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/SignatureDelta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples46a6c6e338a1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSignatureDelta.minimal",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.missing:signature",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["signature"])
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.null:signature",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": null,
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["signature"])
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"signature\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicSignatureDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSignatureDelta.collision",
            input: """
                {
                  \"signature\": \"wire sample\",
                  \"type\": \"signature_delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["signature"])
        ) { json in
            var value = try AnthropicSignatureDelta(wireJSON: json)
            value.additionalFields["signature"] = .null
            return try value.wireJSON()
        },
    ]
}
