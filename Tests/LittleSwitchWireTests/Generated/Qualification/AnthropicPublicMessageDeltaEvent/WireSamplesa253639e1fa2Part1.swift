// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/RawMessageDeltaEvent
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: da832b2296ffaf3c730c1887498e01c9848ccabac340b98b6f6f04ce79a74e68
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa253639e1fa2Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicPublicMessageDeltaEvent.minimal",
            input: """
                {
                  \"delta\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.full",
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
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.missing:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.null:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": null,
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
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.missing:type",
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
                  \"usage\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.null:type",
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
                  \"type\": null,
                  \"usage\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.missing:usage",
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
                  \"type\": \"message_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["usage"])
        ) { json in
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicPublicMessageDeltaEvent.null:usage",
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
                  \"type\": \"message_delta\",
                  \"usage\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicPublicMessageDeltaEvent(wireJSON: json).wireJSON()
        },
    ]
}
