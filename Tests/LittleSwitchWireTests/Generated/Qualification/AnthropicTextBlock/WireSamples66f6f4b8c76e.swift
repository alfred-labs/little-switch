// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/TextBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples66f6f4b8c76e {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicTextBlock.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citations\": [],
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.null:citations",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citations\": null,
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citations\": [],
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citations\": [],
                  \"text\": null,
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citations\": [],
                  \"text\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"citations\": [],
                  \"text\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicTextBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextBlock.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["citations"])
        ) { json in
            var value = try AnthropicTextBlock(wireJSON: json)
            value.additionalFields["citations"] = .null
            return try value.wireJSON()
        },
    ]
}
