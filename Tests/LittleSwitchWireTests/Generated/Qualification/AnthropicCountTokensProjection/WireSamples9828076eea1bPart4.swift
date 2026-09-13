// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/MessageCountTokensParams
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: ebd3a9f08e226c4cec454c33a1e24756bbc2ea35a1f9fc60ef32a5ee2e508db5
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples9828076eea1bPart4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicCountTokensProjection.null:tools",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"cache_control\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"messages\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"model\": \"wire sample\",
                  \"output_config\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"system\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"thinking\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_choice\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tools\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicCountTokensProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicCountTokensProjection.collision",
            input: """
                {
                  \"messages\": [],
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["cache_control"])
        ) { json in
            var value = try AnthropicCountTokensProjection(wireJSON: json)
            value.additionalFields["cache_control"] = .null
            return try value.wireJSON()
        },
    ]
}
