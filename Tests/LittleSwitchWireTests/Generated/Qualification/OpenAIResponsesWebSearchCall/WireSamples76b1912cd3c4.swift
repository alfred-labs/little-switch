// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionWebSearch
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples76b1912cd3c4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesWebSearchCall.minimal",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.null:action",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": null,
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["action"])
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.missing:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"status\": \"in_progress\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: .init(.missingField, path: ["id"])
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.null:id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"id\": null,
                  \"status\": \"in_progress\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["id"])
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.null:status",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"id\": \"wire sample\",
                  \"status\": null,
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"action\": {
                    \"type\": \"search\"
                  },
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesWebSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCall.collision",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"web_search_call\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["action"])
        ) { json in
            var value = try OpenAIResponsesWebSearchCall(wireJSON: json)
            value.additionalFields["action"] = .null
            return try value.wireJSON()
        },
    ]
}
