// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/ResponseStatus
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: e7bbacb6bd0149ef6d886363a8327b15222a1b9e222599ae9ad52eb455735d9a
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb19abfefab96 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesStatus.enum:completed",
            input: """
                \"completed\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesStatus.enum:failed",
            input: """
                \"failed\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesStatus.enum:in_progress",
            input: """
                \"in_progress\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesStatus.enum:cancelled",
            input: """
                \"cancelled\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesStatus.enum:queued",
            input: """
                \"queued\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesStatus.enum:incomplete",
            input: """
                \"incomplete\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesStatus.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesStatus(wireJSON: json).wireJSON()
        },
    ]
}
