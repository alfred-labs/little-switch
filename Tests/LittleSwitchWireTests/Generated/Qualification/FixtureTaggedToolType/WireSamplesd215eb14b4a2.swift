// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Tool/properties/type
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: c99ce03793b5a91196f7bb3e0422a47aae02dadb5492bfd53a040e33c6fc843c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesd215eb14b4a2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureTaggedToolType.enum:tool",
            input: """
                \"tool\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureTaggedToolType(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedToolType.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureTaggedToolType(wireJSON: json).wireJSON()
        },
    ]
}
