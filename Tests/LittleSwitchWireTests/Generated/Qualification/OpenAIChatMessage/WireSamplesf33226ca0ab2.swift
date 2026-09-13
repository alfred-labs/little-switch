// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletionMessage
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf33226ca0ab2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatMessage.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": \"wire sample\",
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessage.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"refusal\": \"wire sample\",
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessage.null:refusal",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": null,
                  \"tool_calls\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessage.null:tool_calls",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"refusal\": \"wire sample\",
                  \"tool_calls\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatMessage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatMessage.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try OpenAIChatMessage(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
