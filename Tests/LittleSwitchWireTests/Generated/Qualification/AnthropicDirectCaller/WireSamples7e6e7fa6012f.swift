// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/DirectCaller
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: d067b2a02899525ef822b0ca67103f1447935a87aaa85d0c978433fe57926ea0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7e6e7fa6012f {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicDirectCaller.minimal",
            input: """
                {
                  \"type\": \"direct\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDirectCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDirectCaller.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"direct\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicDirectCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDirectCaller.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicDirectCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDirectCaller.missing:type",
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
            return try AnthropicDirectCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDirectCaller.null:type",
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
            return try AnthropicDirectCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicDirectCaller.collision",
            input: """
                {
                  \"type\": \"direct\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try AnthropicDirectCaller(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
