// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessageToolCall
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples059e445f659b {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatMessageToolCall.branch:0",
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
            return try OpenAIChatMessageToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessageToolCall.malformed-branch:0",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"function\"
                }
                """,
            expectedError: .init(.missingField, path: ["function"])
        ) { json in
            return try OpenAIChatMessageToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessageToolCall.branch:1",
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
            return try OpenAIChatMessageToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessageToolCall.malformed-branch:1",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"custom\"
                }
                """,
            expectedError: .init(.missingField, path: ["custom"])
        ) { json in
            return try OpenAIChatMessageToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessageToolCall.unknown",
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
            return try OpenAIChatMessageToolCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessageToolCall.unknown-mismatch",
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
            return try OpenAIChatMessageToolCall.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessageToolCall.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIChatMessageToolCall(wireJSON: json).wireJSON()
        },
    ]
}
