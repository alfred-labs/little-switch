// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseInputItem.FunctionCallOutput
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: ae8b4a1f5e59951b12c8cb7454dbfd1ad310863c7f64b28284b47921355af049
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesfcf24739fb10Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputFunctionOutput.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesInputFunctionOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionOutput.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesInputFunctionOutput(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputFunctionOutput.collision",
            input: """
                {
                  \"output\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"function_call_output\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["call_id"])
        ) { json in
            var value = try OpenAIResponsesInputFunctionOutput(wireJSON: json)
            value.additionalFields["call_id"] = .null
            return try value.wireJSON()
        },
    ]
}
