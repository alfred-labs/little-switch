// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Message
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 157ab523b0398d0cf0464ba86d033881472c6f556ccb9d1c700431f802ad5f05
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples54a211a51b66Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessage.minimal",
            input: """
                {
                  \"content\": [],
                  \"id\": \"wire sample\",
                  \"usage\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"id\": \"wire sample\",
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": {
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
            expectedError: nil
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.missing:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": {
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
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"id\": \"wire sample\",
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": {
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
            expectedError: .init(.unexpectedNull, path: ["content"])
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": {
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
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"id\": null,
                  \"stop_reason\": \"end_turn\",
                  \"stop_sequence\": {
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
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
    ]
}
