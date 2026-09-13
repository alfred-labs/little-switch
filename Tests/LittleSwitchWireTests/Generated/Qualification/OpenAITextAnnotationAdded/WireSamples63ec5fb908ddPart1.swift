// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseOutputTextAnnotationAddedEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples63ec5fb908ddPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAITextAnnotationAdded.minimal",
            input: """
                {
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": 9007199254740993,
                  \"content_index\": 9007199254740993,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": 1e400,
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.missing:annotation",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": 1e400,
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["annotation"])
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.null:annotation",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation\": null,
                  \"annotation_index\": 1e400,
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.missing:annotation_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["annotation_index"])
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.null:annotation_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": null,
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["annotation_index"])
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.missing:content_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: .init(.missingField, path: ["content_index"])
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAITextAnnotationAdded.null:content_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"annotation_index\": 1e400,
                  \"content_index\": null,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.output_text.annotation.added\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["content_index"])
        ) { json in
            return try OpenAITextAnnotationAdded(wireJSON: json).wireJSON()
        },
    ]
}
