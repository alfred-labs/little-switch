// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseReasoningSummaryPartDoneEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9f3eaba052f4Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningSummaryPartDone.null:status",
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
                  \"status\": null,
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["status"])
        ) { json in
            return try OpenAIReasoningSummaryPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartDone.missing:summary_index",
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
                  \"status\": \"incomplete\",
                  \"type\": \"response.reasoning_summary_part.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["summary_index"])
        ) { json in
            return try OpenAIReasoningSummaryPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartDone.null:summary_index",
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
                  \"status\": \"incomplete\",
                  \"summary_index\": null,
                  \"type\": \"response.reasoning_summary_part.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["summary_index"])
        ) { json in
            return try OpenAIReasoningSummaryPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartDone.missing:type",
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
                  \"status\": \"incomplete\",
                  \"summary_index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIReasoningSummaryPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartDone.null:type",
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
                  \"status\": \"incomplete\",
                  \"summary_index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIReasoningSummaryPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryPartDone.collision",
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
                  \"type\": \"response.reasoning_summary_part.done\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["item_id"])
        ) { json in
            var value = try OpenAIReasoningSummaryPartDone(wireJSON: json)
            value.additionalFields["item_id"] = .null
            return try value.wireJSON()
        },
    ]
}
