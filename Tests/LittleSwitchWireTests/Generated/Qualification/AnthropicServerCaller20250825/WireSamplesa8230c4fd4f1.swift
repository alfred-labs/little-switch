// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolCaller
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: d067b2a02899525ef822b0ca67103f1447935a87aaa85d0c978433fe57926ea0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa8230c4fd4f1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerCaller20250825.minimal",
            input: """
                {
                  \"tool_id\": \"wire sample\",
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_id\": \"wire sample\",
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.missing:tool_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_id"])
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.null:tool_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_id\": null,
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_id"])
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_id\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_id\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicServerCaller20250825(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerCaller20250825.collision",
            input: """
                {
                  \"tool_id\": \"wire sample\",
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["tool_id"])
        ) { json in
            var value = try AnthropicServerCaller20250825(wireJSON: json)
            value.additionalFields["tool_id"] = .null
            return try value.wireJSON()
        },
    ]
}
