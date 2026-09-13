// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputRefusal/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc2b82cbfe646 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesRefusalType.enum:refusal",
            input: """
                \"refusal\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusalType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesRefusalType(wireJSON: json).wireJSON()
        },
    ]
}
