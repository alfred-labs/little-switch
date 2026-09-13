// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ToolUseBlock/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples3fb550000a95 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolUseBlockType.enum:tool_use",
            input: """
                \"tool_use\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolUseBlockType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolUseBlockType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicToolUseBlockType(wireJSON: json).wireJSON()
        },
    ]
}
