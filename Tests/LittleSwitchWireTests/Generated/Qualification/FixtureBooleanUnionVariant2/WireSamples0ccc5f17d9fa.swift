// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/BooleanUnion/oneOf/1
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 0a4d8f28ddfcf6769012779c777106a2c233817b137b104e5ea168dccf4a645d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0ccc5f17d9fa {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureBooleanUnionVariant2.literal",
            input: """
                false
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanUnionVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanUnionVariant2.invalid-literal",
            input: """
                true
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureBooleanUnionVariant2(wireJSON: json).wireJSON()
        },
    ]
}
