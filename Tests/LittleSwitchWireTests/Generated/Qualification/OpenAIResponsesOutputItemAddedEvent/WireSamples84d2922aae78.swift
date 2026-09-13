// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseOutputItemAddedEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples84d2922aae78 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.minimal",
            input: """
                {
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.missing:item",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["item"])
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.null:item",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item\": null,
                  \"output_index\": 1e400,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.missing:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["output_index"])
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.null:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": null,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesOutputItemAddedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesOutputItemAddedEvent.collision",
            input: """
                {
                  \"item\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.output_item.added\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["item"])
        ) { json in
            var value = try OpenAIResponsesOutputItemAddedEvent(wireJSON: json)
            value.additionalFields["item"] = .null
            return try value.wireJSON()
        },
    ]
}
