// Generated codec qualification. Do not edit.
// Source: OpenAIChatCompletion #/definitions/CompletionUsage
// SDK: openai 7.15.0
// Schema SHA256: d089812c65bd01bb879c0918b284b3e272f89cfde292c3111e05fcf25bf8ad35
// Projection SHA256: f1bbb106f0166bdaee79855b288732e256eb77a1c0220b0086a23e7ddea5948b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd1efbfcc9cf4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIChatBufferedUsage.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.null:completion_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": null,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["completion_tokens"])
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.null:completion_tokens_details",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": null,
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.null:prompt_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": null,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["prompt_tokens"])
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.null:prompt_tokens_details",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": null,
                  \"total_tokens\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.null:total_tokens",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completion_tokens\": 1e400,
                  \"completion_tokens_details\": {},
                  \"prompt_tokens\": 1e400,
                  \"prompt_tokens_details\": {},
                  \"total_tokens\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIChatBufferedUsage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIChatBufferedUsage.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["completion_tokens"])
        ) { json in
            var value = try OpenAIChatBufferedUsage(wireJSON: json)
            value.additionalFields["completion_tokens"] = .null
            return try value.wireJSON()
        },
    ]
}
