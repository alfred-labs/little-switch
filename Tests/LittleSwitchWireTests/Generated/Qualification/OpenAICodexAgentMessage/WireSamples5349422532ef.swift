// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/EasyInputMessage
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: a05c91762a37c85b3dc9173ad20a968bf72046cc9ba7a51d1417ae22c77f4732
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5349422532ef {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAICodexAgentMessage.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAICodexAgentMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAICodexAgentMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAICodexAgentMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessage.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAICodexAgentMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessage.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAICodexAgentMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICodexAgentMessage.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAICodexAgentMessage(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
