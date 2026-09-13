// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/NullableOne/properties/value/oneOf/0
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: d1ee94f3dffcd9b7e5d961aae2ff4deafef58ed59b2569b1c2b8d46ab53335b6
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesfea129bfb99d {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNullableOneValue.enum:yes",
            input: """
                \"yes\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableOneValue(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableOneValue.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureNullableOneValue(wireJSON: json).wireJSON()
        },
    ]
}
