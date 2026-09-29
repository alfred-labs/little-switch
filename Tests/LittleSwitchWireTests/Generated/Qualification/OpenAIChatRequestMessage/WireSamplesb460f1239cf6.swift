// Generated codec qualification. Do not edit.
// Source: OpenAIChatMessage #/definitions/ChatCompletionMessageParam
// SDK: openai 7.15.0
// Schema SHA256: 1c8afefdf7eb6e33f75a1f7cd15678903eed24156ab3c3b87e81928bd51177de
// Projection SHA256: 4aefd73f145963b44c7791bda49a7f65b402452a35350f11d724e561a5b62ab7
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb460f1239cf6 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestMessage.branch:0",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"developer\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.malformed-branch:0",
            input: """
                {
                  \"role\": \"developer\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.branch:1",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"system\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.malformed-branch:1",
            input: """
                {
                  \"role\": \"system\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.branch:2",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"user\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.malformed-branch:2",
            input: """
                {
                  \"role\": \"user\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.branch:3",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"refusal\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"tool_calls\": [
                    {
                      \"function\": {
                        \"arguments\": \"wire sample\",
                        \"name\": \"wire sample\"
                      },
                      \"id\": \"wire sample\",
                      \"type\": \"function\"
                    }
                  ]
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.branch:4",
            input: """
                {
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.malformed-branch:4",
            input: """
                {
                  \"role\": \"tool\",
                  \"tool_call_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIChatRequestMessage.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestMessage.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try OpenAIChatRequestMessage(wireJSON: json).wireJSON()
        },
    ]
}
