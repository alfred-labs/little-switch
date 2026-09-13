// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionMessageCustomToolCall
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples707c2bff66bc {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestCustomCall.minimal",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.full",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.missing:custom",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.null:custom",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.missing:id",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.null:id",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.missing:type",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.null:type",
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
            return try OpenAIChatRequestCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustomCall.collision",
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
            var value = try OpenAIChatRequestCustomCall(wireJSON: json)
            value.additionalFields["custom"] = .null
            return try value.wireJSON()
        },
    ]
}
