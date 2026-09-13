// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/ChatCompletionChunk.Choice/properties/finish_reason/compatibility/chat-provider-finish-reasons/value
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesee608d8d01fa {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatFinishReason.enum:stop",
            input: """
                \"stop\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:length",
            input: """
                \"length\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:tool_calls",
            input: """
                \"tool_calls\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:content_filter",
            input: """
                \"content_filter\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:function_call",
            input: """
                \"function_call\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:sensitive",
            input: """
                \"sensitive\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:model_context_window_exceeded",
            input: """
                \"model_context_window_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.enum:network_error",
            input: """
                \"network_error\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatFinishReason.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatFinishReason(wireJSON: json).wireJSON()
        },
    ]
}
