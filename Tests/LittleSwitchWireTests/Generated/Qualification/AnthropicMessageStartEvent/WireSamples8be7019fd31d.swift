// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageStartEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8be7019fd31d {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageStartEvent.minimal",
            input: """
                {
                  \"message\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"message_start\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"message_start\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.missing:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"message_start\"
                }
                """,
            expectedError: .init(.missingField, path: ["message"])
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.null:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": null,
                  \"type\": \"message_start\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicMessageStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageStartEvent.collision",
            input: """
                {
                  \"message\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"message_start\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["message"])
        ) { json in
            var value = try AnthropicMessageStartEvent(wireJSON: json)
            value.additionalFields["message"] = .null
            return try value.wireJSON()
        },
    ]
}
