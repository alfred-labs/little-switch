// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/EasyInputMessage
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 61dc36bc2cfcdf20eb04cef51032bb3c3b0a2f0d2661d0c3fcc3611c1a0b520e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples67a2782508d0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesUserMessage.minimal",
            input: """
                {
                  \"content\": \"wire sample\",
                  \"role\": \"user\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"role\": \"user\",
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.missing:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"user\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"role\": \"user\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content"])
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.missing:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.null:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"role\": null,
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["role"])
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"role\": \"user\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesUserMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessage.collision",
            input: """
                {
                  \"content\": \"wire sample\",
                  \"role\": \"user\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIResponsesUserMessage(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
