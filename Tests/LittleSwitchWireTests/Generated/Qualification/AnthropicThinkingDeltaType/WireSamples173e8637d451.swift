// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/ThinkingDelta/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples173e8637d451 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicThinkingDeltaType.enum:thinking_delta",
            input: """
                \"thinking_delta\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingDeltaType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingDeltaType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicThinkingDeltaType(wireJSON: json).wireJSON()
        },
    ]
}
