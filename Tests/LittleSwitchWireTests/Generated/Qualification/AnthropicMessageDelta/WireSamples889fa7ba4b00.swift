// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageDeltaEvent.Delta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples889fa7ba4b00 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageDelta.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicMessageDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageDelta.null:stop_reason",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"stop_reason\": null,
                  \"stop_sequence\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageDelta.open:stop_reason",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"stop_reason\": \"__wire_future_value__\",
                  \"stop_sequence\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageDelta.null:stop_sequence",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageDelta.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["stop_reason"])
        ) { json in
            var value = try AnthropicMessageDelta(wireJSON: json)
            value.additionalFields["stop_reason"] = .null
            return try value.wireJSON()
        },
    ]
}
