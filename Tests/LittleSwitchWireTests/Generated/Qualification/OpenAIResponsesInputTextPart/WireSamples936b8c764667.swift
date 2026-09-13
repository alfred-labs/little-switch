// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseInputText
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: a5354f8b649a0489bc2d0e48f9b4f1a2edfb777e03fdfe893288d65cfc3a70f0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples936b8c764667 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputTextPart.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"input_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": \"input_text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"input_text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": null,
                  \"type\": \"input_text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.missing:type",
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
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.null:type",
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
            return try OpenAIResponsesInputTextPart(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputTextPart.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"input_text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["text"])
        ) { json in
            var value = try OpenAIResponsesInputTextPart(wireJSON: json)
            value.additionalFields["text"] = .null
            return try value.wireJSON()
        },
    ]
}
