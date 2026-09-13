// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/OverlappingOne/oneOf/1
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 3bfc0c92eea8a3282142595532e4b01002558c7d8b732422fa0862d7cb0ad653
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples58650bcc39ae {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureOverlappingOneVariant2.enum:a",
            input: """
                \"a\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOverlappingOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOneVariant2.enum:c",
            input: """
                \"c\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOverlappingOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOneVariant2.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureOverlappingOneVariant2(wireJSON: json).wireJSON()
        },
    ]
}
