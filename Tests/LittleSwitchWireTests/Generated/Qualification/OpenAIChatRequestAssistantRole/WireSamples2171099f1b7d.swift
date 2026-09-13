// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionAssistantMessageParam/properties/role
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples2171099f1b7d {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestAssistantRole.enum:assistant",
            input: """
                \"assistant\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestAssistantRole(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestAssistantRole.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatRequestAssistantRole(wireJSON: json).wireJSON()
        },
    ]
}
