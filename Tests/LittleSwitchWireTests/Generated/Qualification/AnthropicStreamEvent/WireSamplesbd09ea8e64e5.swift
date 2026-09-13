// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageStreamEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 0d9e0b9014adafc925c53da23919464724a3a92e25e9669c2a214afd3a25828e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesbd09ea8e64e5 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicStreamEvent.branch:0",
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
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.malformed-branch:0",
            input: """
                {
                  \"type\": \"message_start\"
                }
                """,
            expectedError: .init(.missingField, path: ["message"])
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.branch:1",
            input: """
                {
                  \"delta\": {},
                  \"type\": \"message_delta\",
                  \"usage\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.malformed-branch:1",
            input: """
                {
                  \"type\": \"message_delta\",
                  \"usage\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.branch:2",
            input: """
                {
                  \"type\": \"message_stop\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.branch:3",
            input: """
                {
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
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.malformed-branch:3",
            input: """
                {
                  \"index\": 1e400,
                  \"type\": \"content_block_start\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_block"])
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.branch:4",
            input: """
                {
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
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.malformed-branch:4",
            input: """
                {
                  \"index\": 1e400,
                  \"type\": \"content_block_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.branch:5",
            input: """
                {
                  \"index\": 1e400,
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.malformed-branch:5",
            input: """
                {
                  \"type\": \"content_block_stop\"
                }
                """,
            expectedError: .init(.missingField, path: ["index"])
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicStreamEvent.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicStreamEvent.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicStreamEvent(wireJSON: json).wireJSON()
        },
    ]
}
