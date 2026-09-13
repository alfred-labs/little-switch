// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseReasoningTextDoneEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb7572ac6ab7ePart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningTextDone.minimal",
            input: """
                {
                  \"content_index\": 9007199254740993,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.missing:content_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.null:content_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": null,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content_index"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.null:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": null,
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.null:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": null,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDone.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": null,
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try OpenAIReasoningTextDone(wireJSON: json).wireJSON()
        },
    ]
}
