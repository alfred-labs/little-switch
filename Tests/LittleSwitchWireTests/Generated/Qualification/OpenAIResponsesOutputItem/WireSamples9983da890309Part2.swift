// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputItem
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9983da890309Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesOutputItem.malformed-branch:4",
            input: """
                {
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"status\": \"in_progress\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.branch:5",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"queued\",
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.malformed-branch:5",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"queued\",
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.unknown",
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
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.unknown-mismatch",
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
            return try OpenAIResponsesOutputItem.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItem.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesOutputItem(wireJSON: json).wireJSON()
        },
    ]
}
