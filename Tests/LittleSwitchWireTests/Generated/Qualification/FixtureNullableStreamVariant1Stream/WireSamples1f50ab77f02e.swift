// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/NullableStream/anyOf/0/properties/stream/anyOf/0
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: accd85355b8a637de70a05bf8609e1db772876f5353ced0b7fe751826f018502
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1f50ab77f02e {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNullableStreamVariant1Stream.literal",
            input: """
                false
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStreamVariant1Stream(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1Stream.invalid-literal",
            input: """
                true
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureNullableStreamVariant1Stream(wireJSON: json).wireJSON()
        },
    ]
}
