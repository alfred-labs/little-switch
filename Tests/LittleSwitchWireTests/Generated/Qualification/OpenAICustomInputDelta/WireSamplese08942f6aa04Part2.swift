// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseCustomToolCallInputDeltaEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese08942f6aa04Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAICustomInputDelta.null:output_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": null,
                  \"type\": \"response.custom_tool_call_input.delta\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["output_index"])
        ) { json in
            return try OpenAICustomInputDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICustomInputDelta.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAICustomInputDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICustomInputDelta.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAICustomInputDelta(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAICustomInputDelta.collision",
            input: """
                {
                  \"delta\": \"wire sample\",
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.custom_tool_call_input.delta\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["call_id"])
        ) { json in
            var value = try OpenAICustomInputDelta(wireJSON: json)
            value.additionalFields["call_id"] = .null
            return try value.wireJSON()
        },
    ]
}
