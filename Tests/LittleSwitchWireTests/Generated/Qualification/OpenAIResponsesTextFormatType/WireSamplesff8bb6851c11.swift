// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ResponseFormatText/properties/type
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: 0ec26e62b64051fb756dba956833355e03e1967de3f23f169b9e3660f3d1a9ac
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesff8bb6851c11 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesTextFormatType.enum:text",
            input: """
                \"text\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTextFormatType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextFormatType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesTextFormatType(wireJSON: json).wireJSON()
        },
    ]
}
