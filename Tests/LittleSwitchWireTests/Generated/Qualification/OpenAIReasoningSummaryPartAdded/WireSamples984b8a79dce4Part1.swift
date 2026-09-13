// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseReasoningSummaryPartAddedEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples984b8a79dce4Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningSummaryPartAdded.minimal",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary_index\": 9007199254740993,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.null:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": null,
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.null:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": null,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.missing:part",
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
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["part"])
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartAdded.null:part",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": null,
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningSummaryPartAdded(wireJSON: json).wireJSON()
        },
    ]
}
