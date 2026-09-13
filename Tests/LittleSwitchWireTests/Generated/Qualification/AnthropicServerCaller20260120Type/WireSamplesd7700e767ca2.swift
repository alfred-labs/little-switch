// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolCaller20260120/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: d067b2a02899525ef822b0ca67103f1447935a87aaa85d0c978433fe57926ea0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd7700e767ca2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerCaller20260120Type.enum:code_execution_20260120",
            input: """
                \"code_execution_20260120\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerCaller20260120Type(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20260120Type.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicServerCaller20260120Type(wireJSON: json).wireJSON()
        },
    ]
}
