// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseUsage
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesae04254f2d3d {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesWireUsage.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": 1e400,
                  \"input_tokens_details\": {
                    \"cached_tokens\": 9007199254740993
                  },
                  \"output_tokens\": 1e400,
                  \"output_tokens_details\": {
                    \"reasoning_tokens\": 9007199254740993
                  },
                  \"total_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.null:input_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": null,
                  \"input_tokens_details\": {
                    \"cached_tokens\": 9007199254740993
                  },
                  \"output_tokens\": 1e400,
                  \"output_tokens_details\": {
                    \"reasoning_tokens\": 9007199254740993
                  },
                  \"total_tokens\": 1e400
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["input_tokens"])
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.null:input_tokens_details",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": 1e400,
                  \"input_tokens_details\": null,
                  \"output_tokens\": 1e400,
                  \"output_tokens_details\": {
                    \"reasoning_tokens\": 9007199254740993
                  },
                  \"total_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.null:output_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": 1e400,
                  \"input_tokens_details\": {
                    \"cached_tokens\": 9007199254740993
                  },
                  \"output_tokens\": null,
                  \"output_tokens_details\": {
                    \"reasoning_tokens\": 9007199254740993
                  },
                  \"total_tokens\": 1e400
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_tokens"])
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.null:output_tokens_details",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": 1e400,
                  \"input_tokens_details\": {
                    \"cached_tokens\": 9007199254740993
                  },
                  \"output_tokens\": 1e400,
                  \"output_tokens_details\": null,
                  \"total_tokens\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.null:total_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input_tokens\": 1e400,
                  \"input_tokens_details\": {
                    \"cached_tokens\": 9007199254740993
                  },
                  \"output_tokens\": 1e400,
                  \"output_tokens_details\": {
                    \"reasoning_tokens\": 9007199254740993
                  },
                  \"total_tokens\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["total_tokens"])
        ) { json in
            return try OpenAIResponsesWireUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireUsage.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input_tokens"])
        ) { json in
            var value = try OpenAIResponsesWireUsage(wireJSON: json)
            value.additionalFields["input_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
