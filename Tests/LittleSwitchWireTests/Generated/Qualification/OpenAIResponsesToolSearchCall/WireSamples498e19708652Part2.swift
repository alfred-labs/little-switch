// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseToolSearchCall
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples498e19708652Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesToolSearchCall.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"arguments\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"call_id\": \"wire sample\",
                  \"execution\": \"server\",
                  \"id\": \"wire sample\",
                  \"status\": \"in_progress\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIResponsesToolSearchCall(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolSearchCall.collision",
            input: """
                {
                  \"id\": \"wire sample\",
                  \"type\": \"tool_search_call\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["arguments"])
        ) { json in
            var value = try OpenAIResponsesToolSearchCall(wireJSON: json)
            value.additionalFields["arguments"] = .null
            return try value.wireJSON()
        },
    ]
}
