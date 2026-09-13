// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/EasyInputMessage/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: a05c91762a37c85b3dc9173ad20a968bf72046cc9ba7a51d1417ae22c77f4732
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf8d2e57d75b9 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAICodexAgentMessageType.enum:message",
            input: """
                \"message\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAICodexAgentMessageType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessageType.enum:agent_message",
            input: """
                \"agent_message\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAICodexAgentMessageType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessageType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAICodexAgentMessageType(wireJSON: json).wireJSON()
        },
    ]
}
