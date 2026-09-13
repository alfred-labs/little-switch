// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Usage/properties/service_tier/type/0
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: c4a71a16dacdddda5aabdc87a187a0994f0609d4dd740cfa0faa458ee384bb71
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa770bf16e564 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServiceTier.enum:standard",
            input: """
                \"standard\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServiceTier(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServiceTier.enum:priority",
            input: """
                \"priority\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServiceTier(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServiceTier.enum:batch",
            input: """
                \"batch\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServiceTier(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServiceTier.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicServiceTier(wireJSON: json).wireJSON()
        },
    ]
}
