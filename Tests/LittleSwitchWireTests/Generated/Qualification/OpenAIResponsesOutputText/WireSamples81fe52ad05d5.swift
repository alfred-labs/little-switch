// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples81fe52ad05d5 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesOutputText.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": [],
                  \"logprobs\": [],
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.null:annotations",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": null,
                  \"logprobs\": [],
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.null:logprobs",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": [],
                  \"logprobs\": null,
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": [],
                  \"logprobs\": [],
                  \"type\": \"output_text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": [],
                  \"logprobs\": [],
                  \"text\": null,
                  \"type\": \"output_text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": [],
                  \"logprobs\": [],
                  \"text\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotations\": [],
                  \"logprobs\": [],
                  \"text\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesOutputText(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputText.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["annotations"])
        ) { json in
            var value = try OpenAIResponsesOutputText(wireJSON: json)
            value.additionalFields["annotations"] = .null
            return try value.wireJSON()
        },
    ]
}
