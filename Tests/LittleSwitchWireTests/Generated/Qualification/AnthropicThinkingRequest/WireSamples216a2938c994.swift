// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/MessageCountTokensParams
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: fec4acfe2c5e4e5e6da8e260eae299ff0b3652ffcec38e650f98234cfeb9699b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples216a2938c994 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicThinkingRequest.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingRequest.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_config\": {},
                  \"reasoning_effort\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": {
                    \"type\": \"disabled\"
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingRequest.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicThinkingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingRequest.null:output_config",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_config\": null,
                  \"reasoning_effort\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": {
                    \"type\": \"disabled\"
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_config"])
        ) { json in
            return try AnthropicThinkingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingRequest.null:reasoning_effort",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_config\": {},
                  \"reasoning_effort\": null,
                  \"thinking\": {
                    \"type\": \"disabled\"
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicThinkingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingRequest.null:thinking",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"output_config\": {},
                  \"reasoning_effort\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["thinking"])
        ) { json in
            return try AnthropicThinkingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicThinkingRequest.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["output_config"])
        ) { json in
            var value = try AnthropicThinkingRequest(wireJSON: json)
            value.additionalFields["output_config"] = .null
            return try value.wireJSON()
        },
    ]
}
