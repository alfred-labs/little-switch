// Generated codec qualification. Do not edit.
// Source: OpenAIChatChunk #/definitions/CompletionUsage.CompletionTokensDetails
// SDK: openai 7.15.0
// Schema SHA256: f98b2133df86bdc3c79961c442f51881a69a75aecf09e34ad49b3d1e60ee3b01
// Projection SHA256: 5f4dfcd450738652bdac5ce04a289dd77e58825193954b2705192e5363d8824e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesdb92c1d890bc {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCompletionTokenDetails.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletionTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionTokenDetails.full",
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
            return try OpenAIChatCompletionTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionTokenDetails.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatCompletionTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionTokenDetails.null:reasoning_tokens",
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
            return try OpenAIChatCompletionTokenDetails(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletionTokenDetails.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["reasoning_tokens"])
        ) { json in
            var value = try OpenAIChatCompletionTokenDetails(wireJSON: json)
            value.additionalFields["reasoning_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
