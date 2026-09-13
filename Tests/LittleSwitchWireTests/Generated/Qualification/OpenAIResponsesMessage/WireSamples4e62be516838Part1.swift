// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputMessage
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4e62be516838Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesMessage.minimal",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.full",
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
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.missing:id",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:id",
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
                  \"id\": null,
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:internal_chat_message_metadata_passthrough",
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
                  \"internal_chat_message_metadata_passthrough\": null,
                  \"phase\": \"commentary\",
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["internal_chat_message_metadata_passthrough"])
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesMessage.null:phase",
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
                  \"phase\": null,
                  \"role\": \"assistant\",
                  \"status\": \"in_progress\",
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesMessage(wireJSON: json).wireJSON()
        },
    ]
}
