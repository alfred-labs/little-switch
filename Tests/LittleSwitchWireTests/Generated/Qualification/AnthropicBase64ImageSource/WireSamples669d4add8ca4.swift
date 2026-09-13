// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/Base64ImageSource
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples669d4add8ca4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicBase64ImageSource.minimal",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.missing:data",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: .init(.missingField, path: ["data"])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.null:data",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": null,
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["data"])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.missing:media_type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: .init(.missingField, path: ["media_type"])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.null:media_type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"media_type\": null,
                  \"type\": \"base64\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["media_type"])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"media_type\": \"image/jpeg\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"data\": \"wire sample\",
                  \"media_type\": \"image/jpeg\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicBase64ImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicBase64ImageSource.collision",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["data"])
        ) { json in
            var value = try AnthropicBase64ImageSource(wireJSON: json)
            value.additionalFields["data"] = .null
            return try value.wireJSON()
        },
    ]
}
