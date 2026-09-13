// Generated codec qualification. Do not edit.
// Source: AnthropicMessageParam #/definitions/MessageParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: ba813716dfa815906783146a8e8228fcb6c1eb917c7cedd79803b4981bc59975
// Projection SHA256: 6abd874dc6e8fa342a15ceea5075e38eb220ee0f057fa0099513fedf9ad1013d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesab0203362790 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageParam.minimal",
            input: """
                {
                  \"content\": \"wire sample\",
                  \"role\": \"user\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"role\": \"user\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.missing:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"user\"
                }
                """,
            expectedError: .init(.missingField, path: ["content"])
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.null:content",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": null,
                  \"role\": \"user\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content"])
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.missing:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.null:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content\": \"wire sample\",
                  \"role\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["role"])
        ) { json in
            return try AnthropicMessageParam(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageParam.collision",
            input: """
                {
                  \"content\": \"wire sample\",
                  \"role\": \"user\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content"])
        ) { json in
            var value = try AnthropicMessageParam(wireJSON: json)
            value.additionalFields["content"] = .null
            return try value.wireJSON()
        },
    ]
}
