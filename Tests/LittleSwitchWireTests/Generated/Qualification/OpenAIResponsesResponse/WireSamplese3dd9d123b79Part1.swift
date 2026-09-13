// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/Response
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese3dd9d123b79Part1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesResponse.minimal",
            input: """
                {
                  \"id\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesResponse(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesResponse.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completed_at\": 9007199254740993,
                  \"created_at\": 1e400,
                  \"error\": {
                    \"code\": \"server_error\",
                    \"message\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"incomplete_details\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"response\",
                  \"output\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"status\": \"completed\",
                  \"usage\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesResponse(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesResponse.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesResponse(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesResponse.null:completed_at",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completed_at\": null,
                  \"created_at\": 1e400,
                  \"error\": {
                    \"code\": \"server_error\",
                    \"message\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"incomplete_details\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"response\",
                  \"output\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"status\": \"completed\",
                  \"usage\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesResponse(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesResponse.null:created_at",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completed_at\": 9007199254740993,
                  \"created_at\": null,
                  \"error\": {
                    \"code\": \"server_error\",
                    \"message\": \"wire sample\"
                  },
                  \"id\": \"wire sample\",
                  \"incomplete_details\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"response\",
                  \"output\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"status\": \"completed\",
                  \"usage\": {}
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["created_at"])
        ) { json in
            return try OpenAIResponsesResponse(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesResponse.null:error",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"completed_at\": 9007199254740993,
                  \"created_at\": 1e400,
                  \"error\": null,
                  \"id\": \"wire sample\",
                  \"incomplete_details\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"response\",
                  \"output\": [
                    {
                      \"exact_integer\": 9007199254740993,
                      \"large_number\": 1e400,
                      \"null\": null
                    },
                    null
                  ],
                  \"status\": \"completed\",
                  \"usage\": {}
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesResponse(wireJSON: json).wireJSON()
        },
    ]
}
