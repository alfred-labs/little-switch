// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ToolChoiceAuto/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 5ed50fff4afe63e02ee97dc411bd9fc6b942991e1028c9ce4aa20194b8e0722c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc03d52a85210 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicAutomaticToolChoiceType.enum:auto",
            input: """
                \"auto\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicAutomaticToolChoiceType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicAutomaticToolChoiceType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicAutomaticToolChoiceType(wireJSON: json).wireJSON()
        },
    ]
}
