// Generated codec qualification. Do not edit.
// Source: OpenAIResponseStreamEvent #/definitions/Response.IncompleteDetails/properties/reason
// SDK: openai 7.15.0
// Schema SHA256: a4acd1523e8727a5c3b498809875e8809314f92f7cb346b017e1ca36af17808f
// Projection SHA256: 971f099b3286f4de4a946d154899b421be3e5c70322996da9ad994ae34b88285
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb3f4cf6dbd06 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesIncompleteDetailsReason.enum:max_output_tokens",
            input: """
                \"max_output_tokens\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesIncompleteDetailsReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetailsReason.enum:max_messages",
            input: """
                \"max_messages\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesIncompleteDetailsReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetailsReason.enum:content_filter",
            input: """
                \"content_filter\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesIncompleteDetailsReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetailsReason.enum:steered",
            input: """
                \"steered\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesIncompleteDetailsReason(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesIncompleteDetailsReason.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesIncompleteDetailsReason(wireJSON: json).wireJSON()
        },
    ]
}
