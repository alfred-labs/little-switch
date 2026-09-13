// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/Response.IncompleteDetails
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 971f099b3286f4de4a946d154899b421be3e5c70322996da9ad994ae34b88285
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1c0573efe254 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesIncompleteDetails.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesIncompleteDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetails.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"reason\": \"max_output_tokens\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesIncompleteDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetails.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesIncompleteDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetails.null:reason",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"reason\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["reason"])
        ) { json in
            return try OpenAIResponsesIncompleteDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetails.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["reason"])
        ) { json in
            var value = try OpenAIResponsesIncompleteDetails(wireJSON: json)
            value.additionalFields["reason"] = .null
            return try value.wireJSON()
        },
    ]
}
