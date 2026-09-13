// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/BooleanArray/properties/flags/items
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 65be1b2acc128c2d273f20ccab9d8ce2d20acd711bd4244c6ef6babbaef868d3
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc4996e4748c6 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureBooleanArrayFlagsItem.literal",
            input: """
                true
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanArrayFlagsItem(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanArrayFlagsItem.invalid-literal",
            input: """
                false
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureBooleanArrayFlagsItem(wireJSON: json).wireJSON()
        },
    ]
}
