// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/CitationsSearchResultLocation/properties/type
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: aadc98429ee542042a3d6a5fc24b7f9620494666786e9eff65ba249bf7174a3b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples344f07066e35 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSearchCitationIdentityType.enum:search_result_location",
            input: """
                \"search_result_location\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchCitationIdentityType(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchCitationIdentityType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicSearchCitationIdentityType(wireJSON: json).wireJSON()
        },
    ]
}
