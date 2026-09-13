// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseFunctionToolCall/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 630a9f0d519b1dca6d93b31dc292c8149a62b4910c8e7812d57a39ae56db2969
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples194b65e37e77 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputFunctionCallType.enum:function_call",
            input: """
                \"function_call\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputFunctionCallType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCallType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesInputFunctionCallType(wireJSON: json).wireJSON()
        },
    ]
}
