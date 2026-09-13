// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ThinkingConfigDisabled/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: fec4acfe2c5e4e5e6da8e260eae299ff0b3652ffcec38e650f98234cfeb9699b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesbe53a85cb5e1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicDisabledThinkingType.enum:disabled",
            input: """
                \"disabled\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDisabledThinkingType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDisabledThinkingType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicDisabledThinkingType(wireJSON: json).wireJSON()
        },
    ]
}
