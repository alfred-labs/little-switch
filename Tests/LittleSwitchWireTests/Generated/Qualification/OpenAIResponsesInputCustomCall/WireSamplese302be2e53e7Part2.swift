// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/ResponseCustomToolCall
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 504b9f8e5e1034a5040a5960044d79dd7a57c34c89abbbd57ecaa4a21c0c26d0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese302be2e53e7Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesInputCustomCall.null:namespace",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": null,
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesInputCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomCall.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesInputCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomCall.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesInputCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesInputCustomCall.collision",
            input: """
                {
                  \"call_id\": \"wire sample\",
                  \"input\": \"wire sample\",
                  \"name\": \"wire sample\",
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["call_id"])
        ) { json in
            var value = try OpenAIResponsesInputCustomCall(wireJSON: json)
            value.additionalFields["call_id"] = .null
            return try value.wireJSON()
        },
    ]
}
