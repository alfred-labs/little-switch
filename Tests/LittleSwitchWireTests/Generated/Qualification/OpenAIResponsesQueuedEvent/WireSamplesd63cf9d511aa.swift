// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseQueuedEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd63cf9d511aa {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesQueuedEvent.minimal",
            input: """
                {
                  \"type\": \"response.queued\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesQueuedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesQueuedEvent.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.queued\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesQueuedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesQueuedEvent.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesQueuedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesQueuedEvent.missing:type",
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
            return try OpenAIResponsesQueuedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesQueuedEvent.null:type",
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
            return try OpenAIResponsesQueuedEvent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesQueuedEvent.collision",
            input: """
                {
                  \"type\": \"response.queued\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try OpenAIResponsesQueuedEvent(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
