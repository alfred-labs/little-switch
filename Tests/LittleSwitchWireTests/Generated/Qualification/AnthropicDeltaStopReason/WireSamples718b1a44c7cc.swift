// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageDeltaEvent.Delta/properties/stop_reason/compatibility/anthropic-anthropicstreamevent-rawmessagedeltaevent-delta-stop-reason-openenum/known
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples718b1a44c7cc {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicDeltaStopReason.enum:end_turn",
            input: """
                \"end_turn\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.enum:max_tokens",
            input: """
                \"max_tokens\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.enum:stop_sequence",
            input: """
                \"stop_sequence\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.enum:tool_use",
            input: """
                \"tool_use\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.enum:pause_turn",
            input: """
                \"pause_turn\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.enum:refusal",
            input: """
                \"refusal\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.enum:model_context_window_exceeded",
            input: """
                \"model_context_window_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDeltaStopReason.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicDeltaStopReason(wireJSON: json).wireJSON()
        },
    ]
}
