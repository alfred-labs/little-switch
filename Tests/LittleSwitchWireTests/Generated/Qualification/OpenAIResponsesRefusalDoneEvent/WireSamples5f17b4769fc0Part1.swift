// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseRefusalDoneEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5f17b4769fc0Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.minimal",
            input: """
                {
                  \"content_index\": 9007199254740993,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.full",
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
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.missing:content_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.null:content_index",
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
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content_index"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"output_index\": 1e400,
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.null:item_id",
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
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.null:output_index",
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
                  \"refusal\": \"wire sample\",
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.missing:refusal",
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
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["refusal"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDoneEvent.null:refusal",
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
                  \"refusal\": null,
                  \"type\": \"response.refusal.done\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["refusal"])
        ) { json in
            return try OpenAIResponsesRefusalDoneEvent(wireJSON: json).wireJSON()
        },
    ]
}
