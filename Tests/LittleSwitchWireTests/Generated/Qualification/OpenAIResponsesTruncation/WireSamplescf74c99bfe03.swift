// Generated codec qualification. Do not edit.
// Source: OpenAIResponseRequestBase #/definitions/ResponseCreateParamsBase/properties/truncation/type/0
// SDK: openai 7.15.0
// Schema SHA256: d6c9260f36d822d1a881d033a223917ca6cbf8d9da4b7aa4f6a6cb7991b93f6d
// Projection SHA256: a65162ade22e8100c23f58fef5fb01d2b228b353f71fbf1ef431257f36762bba
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplescf74c99bfe03 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIResponsesTruncation.enum:auto",
            input: """
                \"auto\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTruncation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTruncation.enum:disabled",
            input: """
                \"disabled\"
                """,
            expectedError: nil
        ) { json in
            return try OpenAIResponsesTruncation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIResponsesTruncation.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try OpenAIResponsesTruncation(wireJSON: json).wireJSON()
        },
    ]
}
