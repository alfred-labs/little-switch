// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawContentBlockStartEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf5e95df1ca5d {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicContentBlockStartEvent.minimal",
            input: """
                {
                  \"content_block\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 9007199254740993,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_block\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.missing:content_block",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_block"])
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.null:content_block",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_block\": null,
                  \"index\": 1e400,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.missing:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_block\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: .init(.missingField, path: ["index"])
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.null:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_block\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": null,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["index"])
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_block\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_block\": {
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
            return try AnthropicContentBlockStartEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicContentBlockStartEvent.collision",
            input: """
                {
                  \"content_block\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"index\": 9007199254740993,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content_block"])
        ) { json in
            var value = try AnthropicContentBlockStartEvent(wireJSON: json)
            value.additionalFields["content_block"] = .null
            return try value.wireJSON()
        },
    ]
}
