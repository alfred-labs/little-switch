// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseContentPartDoneEvent
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 19d4efc76fb87cfe514fb7e0fefc8c6ef966dac9b28faa4c611783a4c6acef6a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesde7f7f3aaaa5Part2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIContentPartDone.missing:part",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"type\": \"response.content_part.done\"
                }
                """,
            expectedError: .init(.missingField, path: ["part"])
        ) { json in
            return try OpenAIContentPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContentPartDone.null:part",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": null,
                  \"type\": \"response.content_part.done\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIContentPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContentPartDone.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIContentPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContentPartDone.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"content_index\": 1e400,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 1e400,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIContentPartDone(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContentPartDone.collision",
            input: """
                {
                  \"content_index\": 9007199254740993,
                  \"item_id\": \"wire sample\",
                  \"output_index\": 9007199254740993,
                  \"part\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"response.content_part.done\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["content_index"])
        ) { json in
            var value = try OpenAIContentPartDone(wireJSON: json)
            value.additionalFields["content_index"] = .null
            return try value.wireJSON()
        },
    ]
}
