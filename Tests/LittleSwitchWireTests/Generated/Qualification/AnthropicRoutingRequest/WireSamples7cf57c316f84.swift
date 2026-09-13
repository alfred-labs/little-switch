// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/MessageCountTokensParams
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 574e75636f46350e4d2b08ebfb7f0e9e1f7a152dd6885e729c17879ca5b5fcda
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7cf57c316f84 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicRoutingRequest.minimal",
            input: """
                {
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRoutingRequest.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRoutingRequest.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRoutingRequest.missing:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["model"])
        ) { json in
            return try AnthropicRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRoutingRequest.null:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["model"])
        ) { json in
            return try AnthropicRoutingRequest(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicRoutingRequest.collision",
            input: """
                {
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["model"])
        ) { json in
            var value = try AnthropicRoutingRequest(wireJSON: json)
            value.additionalFields["model"] = .null
            return try value.wireJSON()
        },
    ]
}
