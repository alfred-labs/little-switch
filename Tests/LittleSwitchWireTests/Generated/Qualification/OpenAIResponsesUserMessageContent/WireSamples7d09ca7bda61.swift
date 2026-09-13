// Generated codec qualification. Do not edit.
// Source: OpenAIResponseInput #/definitions/EasyInputMessage/properties/content
// SDK: openai 7.15.0
// Schema SHA256: 870dcd8b84d9a4fcdb3a9435cdaad8e560c959041c4e6f699dea1d9fe1e66bce
// Projection SHA256: 61dc36bc2cfcdf20eb04cef51032bb3c3b0a2f0d2661d0c3fcc3611c1a0b520e
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7d09ca7bda61 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesUserMessageContent.branch:0",
            input: """
                \"wire sample\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageContent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageContent.encode-branch:0",
            input: """
                \"wire sample\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageContent.variant1(String(wireJSON: json)).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageContent.branch:1",
            input: """
                [
                  {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  null
                ]
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageContent(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageContent.encode-branch:1",
            input: """
                [
                  {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  null
                ]
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesUserMessageContent.variant2([JSONValue](wireJSON: json)).wireJSON()
        },
        .init(
            name: "OpenAIResponsesUserMessageContent.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIResponsesUserMessageContent(wireJSON: json).wireJSON()
        },
    ]
}
