// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionWebSearch.Search.Source
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples8953a1a8cb18 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIWebSearchSource.minimal",
            input: """
                {
                  \"type\": \"url\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"url\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null,
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.missing:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"url\"
                }
                """,
            expectedError: .init(.missingField, path: ["url"])
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.null:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"url\",
                  \"url\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["url"])
        ) { json in
            return try OpenAIWebSearchSource(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchSource.collision",
            input: """
                {
                  \"type\": \"url\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try OpenAIWebSearchSource(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
