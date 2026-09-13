// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText/properties/annotations/items
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf44ad73947a6 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAITextAnnotation.branch:0",
            input: """
                {
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": \"file_citation\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotation.branch:1",
            input: """
                {
                  \"end_index\": 1e400,
                  \"start_index\": 1e400,
                  \"title\": \"wire sample\",
                  \"type\": \"url_citation\",
                  \"url\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotation.branch:2",
            input: """
                {
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotation.branch:3",
            input: """
                {
                  \"file_id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": \"file_path\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotation.unknown",
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
            return try OpenAITextAnnotation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotation.unknown-mismatch",
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
            return try OpenAITextAnnotation.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotation.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAITextAnnotation(wireJSON: json).wireJSON()
        },
    ]
}
