// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseCustomToolCall/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 504b9f8e5e1034a5040a5960044d79dd7a57c34c89abbbd57ecaa4a21c0c26d0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8143643a8d57 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputCustomCallType.enum:custom_tool_call",
            input: """
                \"custom_tool_call\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputCustomCallType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomCallType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesInputCustomCallType(wireJSON: json).wireJSON()
        },
    ]
}
