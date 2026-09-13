// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ToolChoiceOptions
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: 15335cb05eedca82e96acf090f29b3a9ed0d911b0b40fe29e9417d6f93c1142c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesefffd0930f69 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesToolChoiceMode.enum:none",
            input: """
                \"none\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolChoiceMode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolChoiceMode.enum:auto",
            input: """
                \"auto\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolChoiceMode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolChoiceMode.enum:required",
            input: """
                \"required\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesToolChoiceMode(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesToolChoiceMode.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesToolChoiceMode(wireJSON: json).wireJSON()
        },
    ]
}
