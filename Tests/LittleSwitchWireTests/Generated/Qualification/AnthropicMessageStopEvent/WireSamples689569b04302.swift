// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageStopEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples689569b04302 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageStopEvent.minimal",
            input: """
                {
                  \"type\": \"message_stop\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"message_stop\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicMessageStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicMessageStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicMessageStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStopEvent.collision",
            input: """
                {
                  \"type\": \"message_stop\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try AnthropicMessageStopEvent(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
