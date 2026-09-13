// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionToolCall
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples923133ca8a5bPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesFunctionCall.null:internal_chat_message_metadata_passthrough",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": null,
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["internal_chat_message_metadata_passthrough"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": null,
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:namespace",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": null,
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:status",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": null,
                  \"type\": \"function_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.collision",
            input: """
                {
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["arguments"])
        ) { json in
            var value = try OpenAIResponsesFunctionCall(wireJSON: json)
            value.additionalFields["arguments"] = .null
            return try value.wireJSON()
        },
    ]
}
