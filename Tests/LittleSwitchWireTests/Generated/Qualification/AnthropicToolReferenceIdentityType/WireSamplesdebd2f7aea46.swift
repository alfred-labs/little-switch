// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ToolReferenceBlockParam/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 6ab17812d982531c6d82a27a80816a5b336174942e2e86082ebbd7d0200b5cde
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesdebd2f7aea46 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolReferenceIdentityType.enum:tool_reference",
            input: """
                \"tool_reference\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolReferenceIdentityType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentityType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicToolReferenceIdentityType(wireJSON: json).wireJSON()
        },
    ]
}
