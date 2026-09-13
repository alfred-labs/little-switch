// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseOutputItemDoneEvent/properties/type
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples56310f7c3217 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesOutputItemDoneEventType.enum:response.output_item.done",
            input: """
                \"response.output_item.done\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItemDoneEventType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemDoneEventType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesOutputItemDoneEventType(wireJSON: json).wireJSON()
        },
    ]
}
