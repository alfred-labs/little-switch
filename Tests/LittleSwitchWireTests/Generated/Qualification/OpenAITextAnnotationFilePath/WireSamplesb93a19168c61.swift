// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText.FilePath
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb93a19168c61 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAITextAnnotationFilePath.minimal",
            input: """
                {
                  \"type\": \"file_path\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"file_id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": \"file_path\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.null:file_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"file_id\": null,
                  \"index\": 1e400,
                  \"type\": \"file_path\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["file_id"])
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.null:index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"file_id\": \"wire sample\",
                  \"index\": null,
                  \"type\": \"file_path\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["index"])
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"file_id\": \"wire sample\",
                  \"index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"file_id\": \"wire sample\",
                  \"index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAITextAnnotationFilePath(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationFilePath.collision",
            input: """
                {
                  \"type\": \"file_path\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["file_id"])
        ) { json in
            var value = try OpenAITextAnnotationFilePath(wireJSON: json)
            value.additionalFields["file_id"] = .null
            return try value.wireJSON()
        },
    ]
}
