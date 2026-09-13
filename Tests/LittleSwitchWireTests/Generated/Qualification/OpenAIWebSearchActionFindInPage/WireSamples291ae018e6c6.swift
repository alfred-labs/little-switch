// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionWebSearch.Find
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples291ae018e6c6 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIWebSearchActionFindInPage.minimal",
            input: """
                {
                  \"type\": \"find_in_page\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"pattern\": \"wire sample\",
                  \"type\": \"find_in_page\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.null:pattern",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"pattern\": null,
                  \"type\": \"find_in_page\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["pattern"])
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"pattern\": \"wire sample\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"pattern\": \"wire sample\",
                  \"type\": null,
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.null:url",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"pattern\": \"wire sample\",
                  \"type\": \"find_in_page\",
                  \"url\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["url"])
        ) { json in
            return try OpenAIWebSearchActionFindInPage(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchActionFindInPage.collision",
            input: """
                {
                  \"type\": \"find_in_page\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["pattern"])
        ) { json in
            var value = try OpenAIWebSearchActionFindInPage(wireJSON: json)
            value.additionalFields["pattern"] = .null
            return try value.wireJSON()
        },
    ]
}
