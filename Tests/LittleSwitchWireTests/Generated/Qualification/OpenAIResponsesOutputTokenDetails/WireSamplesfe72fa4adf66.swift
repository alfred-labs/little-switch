// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseUsage.OutputTokensDetails
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesfe72fa4adf66 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesOutputTokenDetails.minimal",
            input: """
                {
                  \"reasoning_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputTokenDetails.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"reasoning_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputTokenDetails.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesOutputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputTokenDetails.missing:reasoning_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["reasoning_tokens"])
        ) { json in
            return try OpenAIResponsesOutputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputTokenDetails.null:reasoning_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"reasoning_tokens\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["reasoning_tokens"])
        ) { json in
            return try OpenAIResponsesOutputTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputTokenDetails.collision",
            input: """
                {
                  \"reasoning_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["reasoning_tokens"])
        ) { json in
            var value = try OpenAIResponsesOutputTokenDetails(wireJSON: json)
            value.additionalFields["reasoning_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
