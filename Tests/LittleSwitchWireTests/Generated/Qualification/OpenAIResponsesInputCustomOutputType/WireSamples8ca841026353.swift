// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseCustomToolCallOutput/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 4230e2dc659577df8c394911cf9483c11c8c6ecbe06f6662ac63fc0afd4e2df7
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8ca841026353 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputCustomOutputType.enum:custom_tool_call_output",
            input: """
                \"custom_tool_call_output\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputCustomOutputType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutputType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesInputCustomOutputType(wireJSON: json).wireJSON()
        },
    ]
}
