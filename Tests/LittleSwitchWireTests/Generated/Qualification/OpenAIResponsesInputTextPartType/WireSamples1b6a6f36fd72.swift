// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseInputText/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: a5354f8b649a0489bc2d0e48f9b4f1a2edfb777e03fdfe893288d65cfc3a70f0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1b6a6f36fd72 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputTextPartType.enum:input_text",
            input: """
                \"input_text\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputTextPartType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPartType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesInputTextPartType(wireJSON: json).wireJSON()
        },
    ]
}
