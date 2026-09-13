// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Any
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 50de9edefaa15e236fd4eb41da47d47029f2ef63a263c79d7fcdf60524cf8770
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5e5a0a61c6cb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureAny.branch:0",
            input: """
                {
                  \"left\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureAny(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAny.encode-branch:0",
            input: """
                {
                  \"left\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureAny.variant1(FixtureAnyVariant1(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureAny.branch:1",
            input: """
                {
                  \"right\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureAny(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAny.encode-branch:1",
            input: """
                {
                  \"right\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureAny.variant2(FixtureAnyVariant2(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureAny.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureAny(wireJSON: json).wireJSON()
        },
    ]
}
