// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ImageBlockParam/properties/source
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples708a89bdd9d4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicImageSource.branch:0",
            input: """
                {
                  \"data\": \"wire sample\",
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.malformed-branch:0",
            input: """
                {
                  \"media_type\": \"image/jpeg\",
                  \"type\": \"base64\"
                }
                """,
            expectedError: .init(.missingField, path: ["data"])
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.branch:1",
            input: """
                {
                  \"type\": \"url\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.malformed-branch:1",
            input: """
                {
                  \"type\": \"url\"
                }
                """,
            expectedError: .init(.missingField, path: ["url"])
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.branch:2",
            input: """
                {
                  \"file_id\": \"wire sample\",
                  \"type\": \"file\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.malformed-branch:2",
            input: """
                {
                  \"type\": \"file\"
                }
                """,
            expectedError: .init(.missingField, path: ["file_id"])
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.unknown",
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
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.unknown-mismatch",
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
            return try AnthropicImageSource.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicImageSource.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicImageSource(wireJSON: json).wireJSON()
        },
    ]
}
