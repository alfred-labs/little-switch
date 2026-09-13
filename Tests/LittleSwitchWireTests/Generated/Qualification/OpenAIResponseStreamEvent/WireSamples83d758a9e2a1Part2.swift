// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseStreamEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples83d758a9e2a1Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponseStreamEvent.branch:6",
            input: """
                {
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
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:6",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["arguments"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:7",
            input: """
                {
                  \"type\": \"response.in_progress\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:8",
            input: """
                {
                  \"response\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.failed\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:8",
            input: """
                {
                  \"type\": \"response.failed\"
                }
                """,
            expectedError: .init(.missingField, path: ["response"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:9",
            input: """
                {
                  \"response\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.incomplete\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:9",
            input: """
                {
                  \"type\": \"response.incomplete\"
                }
                """,
            expectedError: .init(.missingField, path: ["response"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:10",
            input: """
                {
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:10",
            input: """
                {
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["item"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:11",
            input: """
                {
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:11",
            input: """
                {
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:12",
            input: """
                {
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
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:12",
            input: """
                {
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
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
    ]
}
