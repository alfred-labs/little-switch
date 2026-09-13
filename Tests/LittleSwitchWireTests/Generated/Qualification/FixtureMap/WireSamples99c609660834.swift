// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Map
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 0e98a7991a4913de3d8ad2a234b54ffc4fb8840581a64130fe614801955d8bf6
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples99c609660834 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureMap.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try FixtureMap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureMap.full",
            input: """
                {
                  \"__wire_unknown__\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureMap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureMap.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureMap(wireJSON: json).wireJSON()
        },
    ]
}
