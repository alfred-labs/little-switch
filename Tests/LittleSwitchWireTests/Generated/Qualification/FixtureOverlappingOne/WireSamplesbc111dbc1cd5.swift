// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/OverlappingOne
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 3bfc0c92eea8a3282142595532e4b01002558c7d8b732422fa0862d7cb0ad653
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesbc111dbc1cd5 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureOverlappingOne.branch:0",
            input: """
                \"b\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOverlappingOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOne.encode-branch:0",
            input: """
                \"b\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOverlappingOne.variant1(FixtureOverlappingOneVariant1(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOne.branch:1",
            input: """
                \"c\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOverlappingOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOne.encode-branch:1",
            input: """
                \"c\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOverlappingOne.variant2(FixtureOverlappingOneVariant2(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOne.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureOverlappingOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOverlappingOne.rejected-union",
            input: """
                \"a\"
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureOverlappingOne(wireJSON: json).wireJSON()
        },
    ]
}
