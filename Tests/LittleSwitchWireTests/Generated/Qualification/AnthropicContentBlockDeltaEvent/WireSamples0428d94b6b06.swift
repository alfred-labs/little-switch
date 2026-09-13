// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawContentBlockDeltaEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0428d94b6b06 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlockDeltaEvent.minimal",
            input: """
                {
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 9007199254740993,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.missing:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.null:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": null,
                  \"index\": 1e400,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.missing:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["index"])
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.null:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": null,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["index"])
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": {
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
            return try AnthropicContentBlockDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockDeltaEvent.collision",
            input: """
                {
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 9007199254740993,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["delta"])
        ) { json in
            var value = try AnthropicContentBlockDeltaEvent(wireJSON: json)
            value.additionalFields["delta"] = .null
            return try value.wireJSON()
        },
    ]
}
