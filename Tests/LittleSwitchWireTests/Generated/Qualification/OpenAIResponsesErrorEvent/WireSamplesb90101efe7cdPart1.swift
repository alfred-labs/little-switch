// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseErrorEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb90101efe7cdPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesErrorEvent.minimal",
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
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.missing:code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: .init(.missingField, path: ["code"])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.null:code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": null,
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.missing:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: .init(.missingField, path: ["message"])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.null:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"message\": null,
                  \"param\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["message"])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.missing:param",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"message\": \"wire sample\",
                  \"type\": \"error\"
                }
                """,
            expectedError: .init(.missingField, path: ["param"])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.null:param",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"message\": \"wire sample\",
                  \"param\": null,
                  \"type\": \"error\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesErrorEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"wire sample\",
                  \"message\": \"wire sample\",
                  \"param\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesErrorEvent(wireJSON: json).wireJSON()
        },
    ]
}
