// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ResponseFormatText
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: 0ec26e62b64051fb756dba956833355e03e1967de3f23f169b9e3660f3d1a9ac
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc030a7e3281a {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesTextFormat.minimal",
            input: """
                {
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTextFormat(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextFormat.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTextFormat(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextFormat.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesTextFormat(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextFormat.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesTextFormat(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextFormat.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesTextFormat(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTextFormat.collision",
            input: """
                {
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try OpenAIResponsesTextFormat(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
