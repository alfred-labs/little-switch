// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionToolCall
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples923133ca8a5bPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesFunctionCall.minimal",
            input: """
                {
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.full",
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
                  \"type\": \"function_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.missing:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": null,
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
            expectedError: .init(.unexpectedNull, path: ["arguments"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.missing:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": null,
                  \"encrypted_function_args\": [],
                  \"id\": \"wire sample\",
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:encrypted_function_args",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"encrypted_function_args\": null,
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
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesFunctionCall.null:id",
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
                  \"id\": null,
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIResponsesFunctionCall(wireJSON: json).wireJSON()
        },
    ]
}
