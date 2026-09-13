// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseReasoningTextDeltaEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5cce9953e5e2Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningTextDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIReasoningTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIReasoningTextDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningTextDelta.collision",
            input: """
                {
                  \"content_index\": 9007199254740993,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.reasoning_text.delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content_index"])
        ) { json in
            var value = try OpenAIReasoningTextDelta(wireJSON: json)
            value.additionalFields["content_index"] = .null
            return try value.wireJSON()
        },
    ]
}
