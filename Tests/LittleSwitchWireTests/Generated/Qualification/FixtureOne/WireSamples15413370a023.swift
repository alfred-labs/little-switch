// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/One
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: a812c98cb118986835fa5d1a4b4525a05af563aea5c9014738b4f2d3b478aa73
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples15413370a023 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureOne.branch:0",
            input: """
                {
                  \"left\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOne.encode-branch:0",
            input: """
                {
                  \"left\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOne.variant1(FixtureOneVariant1(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureOne.branch:1",
            input: """
                {
                  \"right\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOne.encode-branch:1",
            input: """
                {
                  \"right\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOne.variant2(FixtureOneVariant2(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureOne.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureOne(wireJSON: json).wireJSON()
        },
    ]
}
