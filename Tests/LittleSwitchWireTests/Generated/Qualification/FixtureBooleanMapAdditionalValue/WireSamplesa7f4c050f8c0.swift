// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/BooleanMap/additionalProperties
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 94e96a78fac32b21aa34b5de57d50fad182f772bf9fb248b41addbeeb80ad3b7
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesa7f4c050f8c0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureBooleanMapAdditionalValue.literal",
            input: """
                true
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanMapAdditionalValue(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanMapAdditionalValue.invalid-literal",
            input: """
                false
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureBooleanMapAdditionalValue(wireJSON: json).wireJSON()
        },
    ]
}
