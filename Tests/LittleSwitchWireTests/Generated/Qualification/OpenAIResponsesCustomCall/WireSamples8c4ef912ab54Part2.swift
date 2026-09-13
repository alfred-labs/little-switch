// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseCustomToolCall
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8c4ef912ab54Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesCustomCall.missing:name",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"namespace\": \"wire sample\",
                  \"status\": \"queued\",
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["name"])
        ) { json in
            return try OpenAIResponsesCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesCustomCall.null:name",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": null,
                  \"namespace\": \"wire sample\",
                  \"status\": \"queued\",
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["name"])
        ) { json in
            return try OpenAIResponsesCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesCustomCall.null:namespace",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": null,
                  \"status\": \"queued\",
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesCustomCall.null:status",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": null,
                  \"type\": \"custom_tool_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesCustomCall.missing:type",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"queued\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesCustomCall.null:type",
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
                  \"internal_chat_message_metadata_passthrough\": {},
                  \"name\": \"wire sample\",
                  \"namespace\": \"wire sample\",
                  \"status\": \"queued\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesCustomCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesCustomCall.collision",
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
            var value = try OpenAIResponsesCustomCall(wireJSON: json)
            value.additionalFields["call_id"] = .null
            return try value.wireJSON()
        },
    ]
}
