// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseReasoningItem.Summary/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: 01c78c049309739f20674a112525772543332fe3b00e87fa0b6db1ebb35226d2
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa76ea640f2d7 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesSummaryPartType.enum:summary_text",
            input: """
                \"summary_text\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesSummaryPartType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesSummaryPartType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesSummaryPartType(wireJSON: json).wireJSON()
        },
    ]
}
