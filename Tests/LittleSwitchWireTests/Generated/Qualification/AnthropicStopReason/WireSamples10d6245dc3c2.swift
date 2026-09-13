// Generated codec qualification. Do not edit.
// Source: AnthropicStopReason #/definitions/StopReason
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 467414680b35b32fecd7385d62dc2e2d19436f2bf3995c25456dad285df2a760
// Projection SHA256: 476d08f4d046aea5f84256fb1ef1a095561ea1ddbb00700b6d6df8c1130e7935
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples10d6245dc3c2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicStopReason.enum:end_turn",
            input: """
                \"end_turn\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.enum:max_tokens",
            input: """
                \"max_tokens\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.enum:stop_sequence",
            input: """
                \"stop_sequence\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.enum:tool_use",
            input: """
                \"tool_use\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.enum:pause_turn",
            input: """
                \"pause_turn\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.enum:refusal",
            input: """
                \"refusal\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.enum:model_context_window_exceeded",
            input: """
                \"model_context_window_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStopReason.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicStopReason(wireJSON: json).wireJSON()
        },
    ]
}
