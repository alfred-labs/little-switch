// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseStreamEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples83d758a9e2a1Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponseStreamEvent.branch:0",
            input: """
                {
                  \"response\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.completed\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:0",
            input: """
                {
                  \"type\": \"response.completed\"
                }
                """,
            expectedError: .init(.missingField, path: ["response"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:1",
            input: """
                {
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.content_part.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:1",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.content_part.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:2",
            input: """
                {
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.content_part.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:2",
            input: """
                {
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.content_part.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:3",
            input: """
                {
                  \"response\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.created\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:3",
            input: """
                {
                  \"type\": \"response.created\"
                }
                """,
            expectedError: .init(.missingField, path: ["response"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:4",
            input: """
                {
                  \"code\": \"wire sample\",
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:4",
            input: """
                {
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: .init(.missingField, path: ["code"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.branch:5",
            input: """
                {
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
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponseStreamEvent.malformed-branch:5",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.function_call_arguments.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try OpenAIResponseStreamEvent(wireJSON: json).wireJSON()
        },
    ]
}
