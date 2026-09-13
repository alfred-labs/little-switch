// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ResponseTextConfig
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: 9d899ad0cd3529d0b0e50f8b83e6980ec6cad70878774fddaf9dab8ca161a02a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples60b6b959280f {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesTextOptions.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTextOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextOptions.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"format\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTextOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextOptions.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesTextOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextOptions.null:format",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"format\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTextOptions(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextOptions.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["format"])
        ) { json in
            var value = try OpenAIResponsesTextOptions(wireJSON: json)
            value.additionalFields["format"] = .null
            return try value.wireJSON()
        },
    ]
}
