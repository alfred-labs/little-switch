// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseFunctionWebSearch/properties/status/compatibility/openairesponsesoutputitem-responsefunctionwebsearch-status-enumvalues/value
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa95f75fff0c1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.enum:in_progress",
            input: """
                \"in_progress\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.enum:searching",
            input: """
                \"searching\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.enum:completed",
            input: """
                \"completed\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.enum:failed",
            input: """
                \"failed\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.enum:incomplete",
            input: """
                \"incomplete\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.enum:queued",
            input: """
                \"queued\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesWebSearchCallStatus.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesWebSearchCallStatus(wireJSON: json).wireJSON()
        },
    ]
}
