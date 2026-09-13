// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/TextBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa4a69c32d528 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicTextParam.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": null,
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.missing:type",
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
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.null:type",
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
            return try AnthropicTextParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicTextParam.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["text"])
        ) { json in
            var value = try AnthropicTextParam(wireJSON: json)
            value.additionalFields["text"] = .null
            return try value.wireJSON()
        },
    ]
}
