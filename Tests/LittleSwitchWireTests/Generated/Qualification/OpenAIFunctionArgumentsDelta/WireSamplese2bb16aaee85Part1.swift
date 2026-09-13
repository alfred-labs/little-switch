// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseFunctionCallArgumentsDeltaEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese2bb16aaee85Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIFunctionArgumentsDelta.minimal",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.null:call_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": null,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.missing:delta",
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
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.null:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": null,
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["delta"])
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.null:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": null,
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": null,
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIFunctionArgumentsDelta.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIFunctionArgumentsDelta(wireJSON: json).wireJSON()
        },
    ]
}
