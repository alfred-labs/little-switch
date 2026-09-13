// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolUseBlock/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 0256884472d43453981d722aaf99b4cf6fb8e448e657c9e96e2742daa727d3f1
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0344ab31b1aa {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicIncomingServerToolUseBlockType.enum:server_tool_use",
            input: """
                \"server_tool_use\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicIncomingServerToolUseBlockType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingServerToolUseBlockType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicIncomingServerToolUseBlockType(wireJSON: json).wireJSON()
        },
    ]
}
