// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Message/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: aa9a21fc811b775d3697333442607b9bebc614411ae0604196b898113dc400fb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples010d2eabb4fb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageMetadataType.enum:message",
            input: """
                \"message\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageMetadataType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadataType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicMessageMetadataType(wireJSON: json).wireJSON()
        },
    ]
}
