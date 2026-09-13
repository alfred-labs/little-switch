// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Recursive/oneOf/0/properties/type
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 04f4624eddfed58d1663253f1757792860cfed68bf91888b340391aa42838497
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples2df1d433cf45 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureRecursiveLeafType.enum:leaf",
            input: """
                \"leaf\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureRecursiveLeafType(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeafType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureRecursiveLeafType(wireJSON: json).wireJSON()
        },
    ]
}
