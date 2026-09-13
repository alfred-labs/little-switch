// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/Base64ImageSource/properties/media_type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesdab3f2c13e08 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicImageMediaType.enum:image/jpeg",
            input: """
                \"image/jpeg\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageMediaType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageMediaType.enum:image/png",
            input: """
                \"image/png\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageMediaType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageMediaType.enum:image/gif",
            input: """
                \"image/gif\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageMediaType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageMediaType.enum:image/webp",
            input: """
                \"image/webp\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicImageMediaType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicImageMediaType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicImageMediaType(wireJSON: json).wireJSON()
        },
    ]
}
