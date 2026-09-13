// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseReasoningSummaryTextDoneEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples79a5a50b2e35Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningSummaryTextDone.minimal",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"summary_index\": 9007199254740993,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.null:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": null,
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.null:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": null,
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.missing:summary_index",
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
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["summary_index"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.null:summary_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": null,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["summary_index"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDone.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"text\": null,
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try OpenAIReasoningSummaryTextDone(wireJSON: json).wireJSON()
        },
    ]
}
