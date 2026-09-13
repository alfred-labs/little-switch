// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Projection/properties/type
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 89033e4b3c8101ff8dcc183c9a63f729a16a830a38986872b8d263a367608a50
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4bf4a3c2c108 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureProjectionType.enum:projected",
            input: """
                \"projected\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureProjectionType(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjectionType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureProjectionType(wireJSON: json).wireJSON()
        },
    ]
}
