// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawContentBlockStopEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa786947b110d {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlockStopEvent.minimal",
            input: """
                {
                  \"index\": 9007199254740993,
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400,
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.missing:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: .init(.missingField, path: ["index"])
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.null:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": null,
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["index"])
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicContentBlockStopEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStopEvent.collision",
            input: """
                {
                  \"index\": 9007199254740993,
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["index"])
        ) { json in
            var value = try AnthropicContentBlockStopEvent(wireJSON: json)
            value.additionalFields["index"] = .null
            return try value.wireJSON()
        },
    ]
}
