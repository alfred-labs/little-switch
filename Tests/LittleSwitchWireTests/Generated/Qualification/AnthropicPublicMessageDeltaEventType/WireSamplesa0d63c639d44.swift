// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageDeltaEvent/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: da832b2296ffaf3c730c1887498e01c9848ccabac340b98b6f6f04ce79a74e68
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa0d63c639d44 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicPublicMessageDeltaEventType.enum:message_delta",
            input: """
                \"message_delta\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPublicMessageDeltaEventType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEventType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicPublicMessageDeltaEventType(wireJSON: json).wireJSON()
        },
    ]
}
