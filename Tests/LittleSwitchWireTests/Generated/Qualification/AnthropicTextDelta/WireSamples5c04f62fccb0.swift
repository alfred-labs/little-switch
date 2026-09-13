// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/TextDelta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5c04f62fccb0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicTextDelta.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": null,
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextDelta.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text_delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["text"])
        ) { json in
            var value = try AnthropicTextDelta(wireJSON: json)
            value.additionalFields["text"] = .null
            return try value.wireJSON()
        },
    ]
}
