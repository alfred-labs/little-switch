// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessageFunctionToolCall/properties/type
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples189ab8613abb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatFunctionCallType.enum:function",
            input: """
                \"function\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFunctionCallType(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFunctionCallType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatFunctionCallType(wireJSON: json).wireJSON()
        },
    ]
}
