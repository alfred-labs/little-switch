// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseReasoningSummaryTextDeltaEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples066452a0d1aePart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningSummaryTextDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIReasoningSummaryTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIReasoningSummaryTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningSummaryTextDelta.collision",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"summary_index\": 9007199254740993,
                  \"type\": \"response.reasoning_summary_text.delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["delta"])
        ) { json in
            var value = try OpenAIReasoningSummaryTextDelta(wireJSON: json)
            value.additionalFields["delta"] = .null
            return try value.wireJSON()
        },
    ]
}
