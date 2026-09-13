// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionWebSearch.Search
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples231420e90515 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIWebSearchActionSearch.minimal",
            input: """
                {
                  \"type\": \"search\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"queries\": [
                    \"wire sample\"
                  ],
                  \"query\": \"wire sample\",
                  \"sources\": [
                    {
                      \"type\": \"url\",
                      \"url\": \"wire sample\"
                    }
                  ],
                  \"type\": \"search\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.null:queries",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"queries\": null,
                  \"query\": \"wire sample\",
                  \"sources\": [
                    {
                      \"type\": \"url\",
                      \"url\": \"wire sample\"
                    }
                  ],
                  \"type\": \"search\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["queries"])
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.null:query",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"queries\": [
                    \"wire sample\"
                  ],
                  \"query\": null,
                  \"sources\": [
                    {
                      \"type\": \"url\",
                      \"url\": \"wire sample\"
                    }
                  ],
                  \"type\": \"search\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["query"])
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.null:sources",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"queries\": [
                    \"wire sample\"
                  ],
                  \"query\": \"wire sample\",
                  \"sources\": null,
                  \"type\": \"search\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["sources"])
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"queries\": [
                    \"wire sample\"
                  ],
                  \"query\": \"wire sample\",
                  \"sources\": [
                    {
                      \"type\": \"url\",
                      \"url\": \"wire sample\"
                    }
                  ]
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"queries\": [
                    \"wire sample\"
                  ],
                  \"query\": \"wire sample\",
                  \"sources\": [
                    {
                      \"type\": \"url\",
                      \"url\": \"wire sample\"
                    }
                  ],
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIWebSearchActionSearch(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionSearch.collision",
            input: """
                {
                  \"type\": \"search\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["queries"])
        ) { json in
            var value = try OpenAIWebSearchActionSearch(wireJSON: json)
            value.additionalFields["queries"] = .null
            return try value.wireJSON()
        },
    ]
}
