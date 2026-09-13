// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/ToolResultBlockParam/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples72fc1506dcbd {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolResultParamType.enum:tool_result",
            input: """
                \"tool_result\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolResultParamType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolResultParamType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicToolResultParamType(wireJSON: json).wireJSON()
        },
    ]
}
