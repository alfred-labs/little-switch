// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseFunctionToolCall
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 630a9f0d519b1dca6d93b31dc292c8149a62b4910c8e7812d57a39ae56db2969
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples146f4158ef47Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputFunctionCall.minimal",
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
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.missing:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["arguments"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.null:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": null,
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["arguments"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.missing:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.null:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": null,
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["call_id"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"id\": null,
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionCall.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": null,
                  \"namespace\": \"wire sample\",
                  \"type\": \"function_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try OpenAIResponsesInputFunctionCall(wireJSON: json).wireJSON()
        },
    ]
}
