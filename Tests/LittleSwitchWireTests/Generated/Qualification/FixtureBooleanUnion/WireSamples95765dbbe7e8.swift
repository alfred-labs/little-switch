// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/BooleanUnion
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 0a4d8f28ddfcf6769012779c777106a2c233817b137b104e5ea168dccf4a645d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples95765dbbe7e8 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureBooleanUnion.branch:0",
            input: """
                true
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanUnion(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanUnion.encode-branch:0",
            input: """
                true
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanUnion.variant1(FixtureBooleanUnionVariant1(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureBooleanUnion.branch:1",
            input: """
                false
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanUnion(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanUnion.encode-branch:1",
            input: """
                false
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanUnion.variant2(FixtureBooleanUnionVariant2(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureBooleanUnion.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureBooleanUnion(wireJSON: json).wireJSON()
        },
    ]
}
