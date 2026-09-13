// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText.Logprob.TopLogprob
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples526a5d42ff73 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesTopLogprob.minimal",
            input: """
                {
                  \"logprob\": 9007199254740993,
                  \"token\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"bytes\": [],
                  \"logprob\": 1e400,
                  \"token\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.null:bytes",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"bytes\": null,
                  \"logprob\": 1e400,
                  \"token\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.missing:logprob",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"bytes\": [],
                  \"token\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["logprob"])
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.null:logprob",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"bytes\": [],
                  \"logprob\": null,
                  \"token\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["logprob"])
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.missing:token",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"bytes\": [],
                  \"logprob\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["token"])
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.null:token",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"bytes\": [],
                  \"logprob\": 1e400,
                  \"token\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["token"])
        ) { json in
            return try OpenAIResponsesTopLogprob(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTopLogprob.collision",
            input: """
                {
                  \"logprob\": 9007199254740993,
                  \"token\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["bytes"])
        ) { json in
            var value = try OpenAIResponsesTopLogprob(wireJSON: json)
            value.additionalFields["bytes"] = .null
            return try value.wireJSON()
        },
    ]
}
