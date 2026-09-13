// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Message/properties/stop_reason/compatibility/anthropic-anthropicmessage-message-stop-reason-openenum/known
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 157ab523b0398d0cf0464ba86d033881472c6f556ccb9d1c700431f802ad5f05
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples76bd0a3a129c {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageStopReason.enum:end_turn",
            input: """
                \"end_turn\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.enum:max_tokens",
            input: """
                \"max_tokens\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.enum:stop_sequence",
            input: """
                \"stop_sequence\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.enum:tool_use",
            input: """
                \"tool_use\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.enum:pause_turn",
            input: """
                \"pause_turn\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.enum:refusal",
            input: """
                \"refusal\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.enum:model_context_window_exceeded",
            input: """
                \"model_context_window_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopReason.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicMessageStopReason(wireJSON: json).wireJSON()
        },
    ]
}
