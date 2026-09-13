// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputRefusal
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples58cafc884e12 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesRefusal.minimal",
            input: """
                {
                  \"refusal\": \"wire sample\",
                  \"type\": \"refusal\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"refusal\": \"wire sample\",
                  \"type\": \"refusal\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.missing:refusal",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"refusal\"
                }
                """,
            expectedError: .init(.missingField, path: ["refusal"])
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.null:refusal",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"refusal\": null,
                  \"type\": \"refusal\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["refusal"])
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"refusal\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"refusal\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesRefusal(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesRefusal.collision",
            input: """
                {
                  \"refusal\": \"wire sample\",
                  \"type\": \"refusal\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["refusal"])
        ) { json in
            var value = try OpenAIResponsesRefusal(wireJSON: json)
            value.additionalFields["refusal"] = .null
            return try value.wireJSON()
        },
    ]
}
