// Generated codec qualification. Do not edit.
// Source: AnthropicStreamEvent #/definitions/InputJSONDelta
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: dbd6e5861026de9cfec261747e3e988ce10802ae7c4bc163574250bae74b1547
// Projection SHA256: 81cb82b66f280f6262374f8a957f482f2c1aed7321c419e6a9bbcd71a99e5f9d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese91438f8d684 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicInputJSONDelta.minimal",
            input: """
                {
                  \"partial_json\": \"wire sample\",
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"partial_json\": \"wire sample\",
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.missing:partial_json",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: .init(.missingField, path: ["partial_json"])
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.null:partial_json",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"partial_json\": null,
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["partial_json"])
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"partial_json\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"partial_json\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicInputJSONDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicInputJSONDelta.collision",
            input: """
                {
                  \"partial_json\": \"wire sample\",
                  \"type\": \"input_json_delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["partial_json"])
        ) { json in
            var value = try AnthropicInputJSONDelta(wireJSON: json)
            value.additionalFields["partial_json"] = .null
            return try value.wireJSON()
        },
    ]
}
