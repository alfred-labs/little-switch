// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ToolUseBlock/properties/caller
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: d067b2a02899525ef822b0ca67103f1447935a87aaa85d0c978433fe57926ea0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples2b17c35f6991 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCaller.branch:0",
            input: """
                {
                  \"type\": \"direct\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.branch:1",
            input: """
                {
                  \"tool_id\": \"wire sample\",
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.malformed-branch:1",
            input: """
                {
                  \"type\": \"code_execution_20250825\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_id"])
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.branch:2",
            input: """
                {
                  \"tool_id\": \"wire sample\",
                  \"type\": \"code_execution_20260120\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.malformed-branch:2",
            input: """
                {
                  \"type\": \"code_execution_20260120\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_id"])
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicCaller.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "AnthropicCaller.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicCaller(wireJSON: json).wireJSON()
        },
    ]
}
