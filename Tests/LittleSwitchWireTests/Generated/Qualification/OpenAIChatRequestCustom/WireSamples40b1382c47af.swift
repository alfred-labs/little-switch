// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionMessageCustomToolCall.Custom
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples40b1382c47af {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestCustom.minimal",
            input: """
                {
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.missing:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.null:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": null,
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["input"])
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.missing:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.null:name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": \"wire sample\",
                  \"name\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try OpenAIChatRequestCustom(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestCustom.collision",
            input: """
                {
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input"])
        ) { json in
            var value = try OpenAIChatRequestCustom(wireJSON: json)
            value.additionalFields["input"] = .null
            return try value.wireJSON()
        },
    ]
}
