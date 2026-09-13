// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessageCustomToolCall
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples6a43761bf405 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCustomCall.minimal",
            input: """
                {
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.missing:custom",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.missingField, path: ["custom"])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.null:custom",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": null,
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["custom"])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": null,
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIChatCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCustomCall.collision",
            input: """
                {
                  \"custom\": {
                    \"input\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["custom"])
        ) { json in
            var value = try OpenAIChatCustomCall(wireJSON: json)
            value.additionalFields["custom"] = .null
            return try value.wireJSON()
        },
    ]
}
