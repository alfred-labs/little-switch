// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletion.Choice/properties/finish_reason
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4ecdd38e7029 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:stop",
            input: """
                \"stop\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:length",
            input: """
                \"length\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:tool_calls",
            input: """
                \"tool_calls\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:content_filter",
            input: """
                \"content_filter\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:function_call",
            input: """
                \"function_call\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:sensitive",
            input: """
                \"sensitive\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:model_context_window_exceeded",
            input: """
                \"model_context_window_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.enum:network_error",
            input: """
                \"network_error\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionFinishReason.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatCompletionFinishReason(wireJSON: json).wireJSON()
        },
    ]
}
