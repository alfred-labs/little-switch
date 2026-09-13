// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: fed0d06792def45574a54293506b348cd9974086fd8fb31fab9759133fc3c24d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesdaaea605671b {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReplayTextPartType.enum:output_text",
            input: """
                \"output_text\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReplayTextPartType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPartType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesReplayTextPartType(wireJSON: json).wireJSON()
        },
    ]
}
