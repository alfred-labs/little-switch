// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseReasoningItem.Content/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b83e22fb373ba1af90eaa1f9f2b4f5081e41d40c2acb54246f9c7fe2cb99e19e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5dab2ed3c2f4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReasoningContentPartType.enum:reasoning_text",
            input: """
                \"reasoning_text\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningContentPartType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPartType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesReasoningContentPartType(wireJSON: json).wireJSON()
        },
    ]
}
