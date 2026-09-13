// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputMessage/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: cecf089fab91450837e11359cea33757d9307d31a79f6de0a460607713097989
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8379f2ebb5c0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReplayMessageType.enum:message",
            input: """
                \"message\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReplayMessageType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayMessageType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesReplayMessageType(wireJSON: json).wireJSON()
        },
    ]
}
