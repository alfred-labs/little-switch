// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/StreamFalse/properties/stream
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 64f11b2129f3785391021bc6b8f28a04843c583515d6afad298e0b45b2cb61c4
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese611c77a4511 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureStreamVariant1Stream.literal",
            input: """
                false
                """,
            expectedError: nil
        ) { json in
            return try FixtureStreamVariant1Stream(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureStreamVariant1Stream.invalid-literal",
            input: """
                true
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureStreamVariant1Stream(wireJSON: json).wireJSON()
        },
    ]
}
