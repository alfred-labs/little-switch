// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Scalar
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 3416db88355a2b8ba04b668da763c2b85ad585d71842d8028aadf4b673f076a6
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples85541cb090fd {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureScalar.branch:0",
            input: """
                \"wire sample\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureScalar(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureScalar.encode-branch:0",
            input: """
                \"wire sample\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureScalar.variant1(String(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureScalar.branch:1",
            input: """
                1e400
                """,
            expectedError: nil
        ) { json in
            return try FixtureScalar(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureScalar.encode-branch:1",
            input: """
                1e400
                """,
            expectedError: nil
        ) { json in
            return try FixtureScalar.variant2(JSONNumber(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureScalar.branch:2",
            input: """
                true
                """,
            expectedError: nil
        ) { json in
            return try FixtureScalar(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureScalar.encode-branch:2",
            input: """
                true
                """,
            expectedError: nil
        ) { json in
            return try FixtureScalar.variant3(Bool(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureScalar.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureScalar(wireJSON: json).wireJSON()
        },
    ]
}
