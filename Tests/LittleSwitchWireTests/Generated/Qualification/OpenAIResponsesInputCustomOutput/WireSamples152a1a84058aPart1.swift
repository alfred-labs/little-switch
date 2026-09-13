// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseCustomToolCallOutput
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 4230e2dc659577df8c394911cf9483c11c8c6ecbe06f6662ac63fc0afd4e2df7
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples152a1a84058aPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputCustomOutput.minimal",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.missing:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: .init(.missingField, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.null:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": null,
                  \"id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": null,
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.missing:output",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: .init(.missingField, path: ["output"])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.null:output",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"output\": null,
                  \"type\": \"custom_tool_call_output\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomOutput.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesInputCustomOutput(wireJSON: json).wireJSON()
        },
    ]
}
