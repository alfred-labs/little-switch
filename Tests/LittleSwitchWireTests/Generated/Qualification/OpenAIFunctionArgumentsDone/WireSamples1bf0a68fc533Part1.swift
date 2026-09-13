// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseFunctionCallArgumentsDoneEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1bf0a68fc533Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIFunctionArgumentsDone.minimal",
            input: """
                {
                  \"arguments\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.missing:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["arguments"])
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.null:arguments",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": null,
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["arguments"])
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.null:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": null,
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.null:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"item_id\": null,
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": null,
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDone.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": \"wire sample\",
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIFunctionArgumentsDone(wireJSON: json).wireJSON()
        },
    ]
}
