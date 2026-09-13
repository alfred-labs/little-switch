// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Message
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 157ab523b0398d0cf0464ba86d033881472c6f556ccb9d1c700431f802ad5f05
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples54a211a51b66Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessage.null:stop_reason",
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
                  \"stop_reason\": null,
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
            name: "AnthropicMessage.open:stop_reason",
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
                  \"stop_reason\": \"__wire_future_value__\",
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
            name: "AnthropicMessage.null:stop_sequence",
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
                  \"stop_sequence\": null,
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
            name: "AnthropicMessage.missing:usage",
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
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["usage"])
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.null:usage",
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
                  \"usage\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessage.collision",
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
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try AnthropicMessage(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
