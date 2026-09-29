// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionMessageFunctionToolCall/properties/type
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: 4aefd73f145963b44c7791bda49a7f65b402452a35350f11d724e561a5b62ab7
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa79a9a1104d4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestFunctionCallType.enum:function",
            input: """
                \"function\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestFunctionCallType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestFunctionCallType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatRequestFunctionCallType(wireJSON: json).wireJSON()
        },
    ]
}
