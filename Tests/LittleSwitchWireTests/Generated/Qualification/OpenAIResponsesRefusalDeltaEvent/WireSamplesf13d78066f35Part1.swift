// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseRefusalDeltaEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf13d78066f35Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.minimal",
            input: """
                {
                  \"content_index\": 9007199254740993,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.full",
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
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.missing:content_index",
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
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.null:content_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": null,
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content_index"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.missing:delta",
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
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["delta"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.null:delta",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"delta\": null,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["delta"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.missing:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["item_id"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.null:item_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"delta\": \"wire sample\",
                  \"item_id\": null,
                  \"output_index\": 1e400,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["item_id"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.missing:output_index",
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
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusalDeltaEvent.null:output_index",
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
                  \"output_index\": null,
                  \"type\": \"response.refusal.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAIResponsesRefusalDeltaEvent(wireJSON: json).wireJSON()
        },
    ]
}
