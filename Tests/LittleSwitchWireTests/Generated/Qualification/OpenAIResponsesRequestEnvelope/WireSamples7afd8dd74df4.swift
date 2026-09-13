// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ResponseCreateParamsBase
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: d67d897534498a86a9e969488bd16f7b739fb67201ded207b85ac267dbedf1f5
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7afd8dd74df4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesRequestEnvelope.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRequestEnvelope.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_choice\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tools\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRequestEnvelope.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRequestEnvelope.null:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": null,
                  \"tool_choice\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tools\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRequestEnvelope.null:tool_choice",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_choice\": null,
                  \"tools\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRequestEnvelope.null:tools",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_choice\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tools\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRequestEnvelope(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRequestEnvelope.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input"])
        ) { json in
            var value = try OpenAIResponsesRequestEnvelope(wireJSON: json)
            value.additionalFields["input"] = .null
            return try value.wireJSON()
        },
    ]
}
