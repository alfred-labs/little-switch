// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseError
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8557284261cb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesWireError.minimal",
            input: """
                {
                  \"code\": \"server_error\",
                  \"message\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"server_error\",
                  \"message\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.missing:code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"message\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["code"])
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.null:code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": null,
                  \"message\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["code"])
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.open:code",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"__wire_future_value__\",
                  \"message\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.missing:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"server_error\"
                }
                """,
            expectedError: .init(.missingField, path: ["message"])
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.null:message",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"code\": \"server_error\",
                  \"message\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["message"])
        ) { json in
            return try OpenAIResponsesWireError(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWireError.collision",
            input: """
                {
                  \"code\": \"server_error\",
                  \"message\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["code"])
        ) { json in
            var value = try OpenAIResponsesWireError(wireJSON: json)
            value.additionalFields["code"] = .null
            return try value.wireJSON()
        },
    ]
}
