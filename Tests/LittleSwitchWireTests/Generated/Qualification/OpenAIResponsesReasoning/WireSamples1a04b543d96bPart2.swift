// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseReasoningItem
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1a04b543d96bPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReasoning.null:internal_chat_message_metadata_passthrough",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": null,
                  \"status\": \"in_progress\",
                  \"summary\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"type\": \"reasoning\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["internal_chat_message_metadata_passthrough"])
        ) { json in
            return try OpenAIResponsesReasoning(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoning.null:status",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"status\": null,
                  \"summary\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"type\": \"reasoning\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoning(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoning.null:summary",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"status\": \"in_progress\",
                  \"summary\": null,
                  \"type\": \"reasoning\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["summary"])
        ) { json in
            return try OpenAIResponsesReasoning(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoning.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"status\": \"in_progress\",
                  \"summary\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ]
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesReasoning(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoning.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"status\": \"in_progress\",
                  \"summary\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesReasoning(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoning.collision",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"reasoning\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIResponsesReasoning(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
