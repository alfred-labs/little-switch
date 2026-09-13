// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseReasoningItem.Content
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b83e22fb373ba1af90eaa1f9f2b4f5081e41d40c2acb54246f9c7fe2cb99e19e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese370fe62c47c {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesReasoningContentPart.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"reasoning_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": \"reasoning_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"reasoning_text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": null,
                  \"type\": \"reasoning_text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.missing:type",
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
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.null:type",
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
            return try OpenAIResponsesReasoningContentPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesReasoningContentPart.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"reasoning_text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["text"])
        ) { json in
            var value = try OpenAIResponsesReasoningContentPart(wireJSON: json)
            value.additionalFields["text"] = .null
            return try value.wireJSON()
        },
    ]
}
