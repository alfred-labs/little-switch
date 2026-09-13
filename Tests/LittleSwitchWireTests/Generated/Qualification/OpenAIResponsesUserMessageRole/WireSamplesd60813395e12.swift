// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/EasyInputMessage/properties/role
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 61dc36bc2cfcdf20eb04cef51032bb3c3b0a2f0d2661d0c3fcc3611c1a0b520e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd60813395e12 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesUserMessageRole.enum:user",
            input: """
                \"user\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageRole(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageRole.enum:assistant",
            input: """
                \"assistant\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageRole(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageRole.enum:system",
            input: """
                \"system\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageRole(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageRole.enum:developer",
            input: """
                \"developer\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageRole(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageRole.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesUserMessageRole(wireJSON: json).wireJSON()
        },
    ]
}
