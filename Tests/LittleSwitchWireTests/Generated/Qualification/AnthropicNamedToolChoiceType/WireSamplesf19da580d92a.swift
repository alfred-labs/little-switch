// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ToolChoiceTool/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: e2b65972c18933bd197b440281af627830410cc632fc64aaadf7c934538cbacb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf19da580d92a {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicNamedToolChoiceType.enum:tool",
            input: """
                \"tool\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicNamedToolChoiceType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicNamedToolChoiceType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicNamedToolChoiceType(wireJSON: json).wireJSON()
        },
    ]
}
