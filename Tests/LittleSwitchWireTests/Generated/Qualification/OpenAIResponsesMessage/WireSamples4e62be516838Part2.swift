// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputMessage
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4e62be516838Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesMessage.missing:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"text\": \"wire sample\",
                      \"type\": \"output_text\"
                    }
                  ],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"text\": \"wire sample\",
                      \"type\": \"output_text\"
                    }
                  ],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": null,
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["role"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:status",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"text\": \"wire sample\",
                      \"type\": \"output_text\"
                    }
                  ],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": null,
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"text\": \"wire sample\",
                      \"type\": \"output_text\"
                    }
                  ],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": [
                    {
                      \"text\": \"wire sample\",
                      \"type\": \"output_text\"
                    }
                  ],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.collision",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIResponsesMessage(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
