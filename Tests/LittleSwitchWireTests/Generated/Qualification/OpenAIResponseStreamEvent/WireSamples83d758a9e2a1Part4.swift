// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseStreamEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples83d758a9e2a1Part4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:19",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:20",
            input: """
                {
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:20",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:21",
            input: """
                {
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.output_text.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:21",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"text\": \"wire sample\",
                  \"type\": \"response.output_text.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:22",
            input: """
                {
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": 1e400,
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:22",
            input: """
                {
                  \"annotation_index\": 1e400,
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["annotation"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:23",
            input: """
                {
                  \"type\": \"response.queued\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:24",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.custom_tool_call_input.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:24",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.custom_tool_call_input.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:25",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.custom_tool_call_input.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:25",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.custom_tool_call_input.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
    ]
}
