// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseStreamEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples83d758a9e2a1Part3 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponseStreamEvent.branch:13",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"status\": \"incomplete\",
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:13",
            input: """
                {
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"status\": \"incomplete\",
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_part.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:14",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_text.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:14",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"type\": \"response.reasoning_summary_text.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:15",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:15",
            input: """
                {
                  \"output_index\": 1e400,
                  \"summary_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_summary_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:16",
            input: """
                {
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.reasoning_text.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:16",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.reasoning_text.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:17",
            input: """
                {
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:17",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.reasoning_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:18",
            input: """
                {
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:18",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:19",
            input: """
                {
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
    ]
}
