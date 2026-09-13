// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseToolSearchCall
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples498e19708652Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesToolSearchCall.minimal",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.null:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": null,
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.null:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": null,
                  \"execution\": \"server\",
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.null:execution",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": null,
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["execution"])
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
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
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"id\": null,
                  \"status\": \"in_progress\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.null:status",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"id\": \"wire sample\",
                  \"status\": null,
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
    ]
}
