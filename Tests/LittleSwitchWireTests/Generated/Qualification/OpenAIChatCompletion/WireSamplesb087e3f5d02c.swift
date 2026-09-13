// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/ChatCompletion
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb087e3f5d02c {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatCompletion.minimal",
            input: """
                {
                  \"choices\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"finish_reason\": \"stop\",
                      \"message\": {}
                    }
                  ],
                  \"created\": 9007199254740993,
                  \"id\": \"wire sample\",
                  \"usage\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.missing:choices",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"created\": 9007199254740993,
                  \"id\": \"wire sample\",
                  \"usage\": {}
                }
                """,
            expectedError: .init(.missingField, path: ["choices"])
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.null:choices",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": null,
                  \"created\": 9007199254740993,
                  \"id\": \"wire sample\",
                  \"usage\": {}
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["choices"])
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.null:created",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"finish_reason\": \"stop\",
                      \"message\": {}
                    }
                  ],
                  \"created\": null,
                  \"id\": \"wire sample\",
                  \"usage\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"finish_reason\": \"stop\",
                      \"message\": {}
                    }
                  ],
                  \"created\": 9007199254740993,
                  \"id\": null,
                  \"usage\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.null:usage",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choices\": [
                    {
                      \"finish_reason\": \"stop\",
                      \"message\": {}
                    }
                  ],
                  \"created\": 9007199254740993,
                  \"id\": \"wire sample\",
                  \"usage\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatCompletion(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatCompletion.collision",
            input: """
                {
                  \"choices\": []
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["choices"])
        ) { json in
            var value = try OpenAIChatCompletion(wireJSON: json)
            value.additionalFields["choices"] = .null
            return try value.wireJSON()
        },
    ]
}
