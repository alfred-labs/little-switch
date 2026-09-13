// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: fed0d06792def45574a54293506b348cd9974086fd8fb31fab9759133fc3c24d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4b2edc00709a {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReplayTextPart.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"output_text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": null,
                  \"type\": \"output_text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesReplayTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReplayTextPart.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"output_text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["text"])
        ) { json in
            var value = try OpenAIResponsesReplayTextPart(wireJSON: json)
            value.additionalFields["text"] = .null
            return try value.wireJSON()
        },
    ]
}
