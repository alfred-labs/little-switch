// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/Reasoning
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: b908fc1548e7ae31cc89a2740902b3594ec63a29f0d07524060bd63531eebad6
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese4d6910c81eb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReasoningOptions.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningOptions.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"effort\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningOptions.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesReasoningOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningOptions.null:effort",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"effort\": null,
                  \"summary\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningOptions.null:summary",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"effort\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"summary\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningOptions.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["effort"])
        ) { json in
            var value = try OpenAIResponsesReasoningOptions(wireJSON: json)
            value.additionalFields["effort"] = .null
            return try value.wireJSON()
        },
    ]
}
