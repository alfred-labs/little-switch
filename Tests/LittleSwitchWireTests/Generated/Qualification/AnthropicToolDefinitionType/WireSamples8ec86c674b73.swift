// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/Tool/properties/type/type/0
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 74783645dc5631624eea4f074e76df445c891d52e9ccacc4c2107e70733cf7fc
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8ec86c674b73 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolDefinitionType.enum:custom",
            input: """
                \"custom\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolDefinitionType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolDefinitionType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicToolDefinitionType(wireJSON: json).wireJSON()
        },
    ]
}
