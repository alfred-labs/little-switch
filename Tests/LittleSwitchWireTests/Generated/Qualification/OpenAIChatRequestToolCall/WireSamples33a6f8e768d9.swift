// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionMessageToolCall
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: a676e4a96ec14a5c179123508486129b68b5862ef10610414b88454a498e89aa
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples33a6f8e768d9 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestToolCall.branch:0",
            input: """
                {
                  \"function\": {
                    \"arguments\": \"wire sample\",
                    \"name\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestToolCall.malformed-branch:0",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.missingField, path: ["function"])
        ) { json in
            return try OpenAIChatRequestToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestToolCall.branch:1",
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
            return try OpenAIChatRequestToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestToolCall.malformed-branch:1",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.missingField, path: ["custom"])
        ) { json in
            return try OpenAIChatRequestToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestToolCall.unknown",
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
            return try OpenAIChatRequestToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestToolCall.unknown-mismatch",
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
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatRequestToolCall.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestToolCall.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIChatRequestToolCall(wireJSON: json).wireJSON()
        },
    ]
}
