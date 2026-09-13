// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputItem
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9983da890309Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesOutputItem.branch:0",
            input: """
                {
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
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.malformed-branch:0",
            input: """
                {
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
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.branch:1",
            input: """
                {
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.malformed-branch:1",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["arguments"])
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.branch:2",
            input: """
                {
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.malformed-branch:2",
            input: """
                {
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"status\": \"in_progress\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.branch:3",
            input: """
                {
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
                  \"type\": \"reasoning\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.malformed-branch:3",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"encrypted_content\": \"wire sample\",
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
                  \"type\": \"reasoning\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.branch:4",
            input: """
                {
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
    ]
}
