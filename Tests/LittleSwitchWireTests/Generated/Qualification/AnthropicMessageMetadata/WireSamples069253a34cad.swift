// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/Message
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: aa9a21fc811b775d3697333442607b9bebc614411ae0604196b898113dc400fb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples069253a34cad {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicMessageMetadata.minimal",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.missing:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.missingField, path: ["model"])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.null:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": null,
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["model"])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.missing:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.missingField, path: ["role"])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.null:role",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"role\": null,
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["role"])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"role\": \"assistant\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicMessageMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicMessageMetadata.collision",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"role\": \"assistant\",
                  \"type\": \"message\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["model"])
        ) { json in
            var value = try AnthropicMessageMetadata(wireJSON: json)
            value.additionalFields["model"] = .null
            return try value.wireJSON()
        },
    ]
}
