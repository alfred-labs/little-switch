// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ToolUseBlock
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 0256884472d43453981d722aaf99b4cf6fb8e448e657c9e96e2742daa727d3f1
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7a102ed80009Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicIncomingToolUseBlock.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"id\": \"wire sample\",
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicIncomingToolUseBlock(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicIncomingToolUseBlock.collision",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"name\": \"wire sample\",
                  \"type\": \"tool_use\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["id"])
        ) { json in
            var value = try AnthropicIncomingToolUseBlock(wireJSON: json)
            value.additionalFields["id"] = .null
            return try value.wireJSON()
        },
    ]
}
