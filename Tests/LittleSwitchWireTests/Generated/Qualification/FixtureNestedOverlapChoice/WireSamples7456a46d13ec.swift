// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/OverlappingOne
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: a6c48b70d904699121cd702687c0f88e554eb2c4945e31258109a60c5e979b8f
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7456a46d13ec {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNestedOverlapChoice.branch:0",
            input: """
                \"b\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureNestedOverlapChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlapChoice.encode-branch:0",
            input: """
                \"b\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureNestedOverlapChoice.variant1(FixtureNestedOverlapChoiceVariant1(wireJSON: json))
                .wireJSON()
        },
        .init(
            name: "FixtureNestedOverlapChoice.branch:1",
            input: """
                \"c\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureNestedOverlapChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlapChoice.encode-branch:1",
            input: """
                \"c\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureNestedOverlapChoice.variant2(FixtureNestedOverlapChoiceVariant2(wireJSON: json))
                .wireJSON()
        },
        .init(
            name: "FixtureNestedOverlapChoice.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNestedOverlapChoice(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlapChoice.rejected-union",
            input: """
                \"a\"
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNestedOverlapChoice(wireJSON: json).wireJSON()
        },
    ]
}
