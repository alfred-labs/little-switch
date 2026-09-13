// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ImageBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples483c16e1a330 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicImageParam.minimal",
            input: """
                {
                  \"source\": {
                    \"data\": \"wire sample\",
                    \"media_type\": \"image/jpeg\",
                    \"type\": \"base64\"
                  },
                  \"type\": \"image\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"source\": {
                    \"data\": \"wire sample\",
                    \"media_type\": \"image/jpeg\",
                    \"type\": \"base64\"
                  },
                  \"type\": \"image\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.missing:source",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"image\"
                }
                """,
            expectedError: .init(.missingField, path: ["source"])
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.null:source",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"source\": null,
                  \"type\": \"image\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["source"])
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"source\": {
                    \"data\": \"wire sample\",
                    \"media_type\": \"image/jpeg\",
                    \"type\": \"base64\"
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"source\": {
                    \"data\": \"wire sample\",
                    \"media_type\": \"image/jpeg\",
                    \"type\": \"base64\"
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicImageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageParam.collision",
            input: """
                {
                  \"source\": {
                    \"data\": \"wire sample\",
                    \"media_type\": \"image/jpeg\",
                    \"type\": \"base64\"
                  },
                  \"type\": \"image\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["source"])
        ) { json in
            var value = try AnthropicImageParam(wireJSON: json)
            value.additionalFields["source"] = .null
            return try value.wireJSON()
        },
    ]
}
