// Generated codec qualification. Do not edit.
// Source: OpenAIChatRequest #/definitions/ChatCompletionCreateParamsNonStreaming
// SDK: openai 7.15.0
// Schema SHA256: 4af502ac02c703ca45709e1c614813be74784c46dad087aa637a267e4b1041be
// Projection SHA256: b64c88c86b2d2aa2e8570be2d753ba6ed39a045cb01a9a9fa87d807585ada09b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesbd26befdbc68 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatRequestEnvelope.minimal",
            input: """
                {
                  \"messages\": [],
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"messages\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.missing:messages",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["messages"])
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.null:messages",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"messages\": null,
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["messages"])
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.missing:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"messages\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ]
                }
                """,
            expectedError: .init(.missingField, path: ["model"])
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.null:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"messages\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"model\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["model"])
        ) { json in
            return try OpenAIChatRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatRequestEnvelope.collision",
            input: """
                {
                  \"messages\": [],
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["messages"])
        ) { json in
            var value = try OpenAIChatRequestEnvelope(wireJSON: json)
            value.additionalFields["messages"] = .null
            return try value.wireJSON()
        },
    ]
}
