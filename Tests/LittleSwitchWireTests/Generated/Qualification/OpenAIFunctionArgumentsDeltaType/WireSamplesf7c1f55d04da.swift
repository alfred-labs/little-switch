// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseFunctionCallArgumentsDeltaEvent/properties/type
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf7c1f55d04da {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIFunctionArgumentsDeltaType.enum:response.function_call_arguments.delta",
            input: """
                \"response.function_call_arguments.delta\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDeltaType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDeltaType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIFunctionArgumentsDeltaType(wireJSON: json).wireJSON()
        },
    ]
}
