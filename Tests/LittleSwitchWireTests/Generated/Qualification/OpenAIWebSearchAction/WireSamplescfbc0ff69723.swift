// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionWebSearch/properties/action
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplescfbc0ff69723 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIWebSearchAction.branch:0",
            input: """
                {
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
            return try OpenAIWebSearchAction(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchAction.branch:1",
            input: """
                {
                  \"type\": \"open_page\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchAction(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchAction.branch:2",
            input: """
                {
                  \"pattern\": \"wire sample\",
                  \"type\": \"find_in_page\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchAction(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchAction.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIWebSearchAction(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchAction.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIWebSearchAction.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "OpenAIWebSearchAction.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIWebSearchAction(wireJSON: json).wireJSON()
        },
    ]
}
