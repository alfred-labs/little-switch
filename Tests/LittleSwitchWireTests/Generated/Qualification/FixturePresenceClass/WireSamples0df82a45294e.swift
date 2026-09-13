// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Presence/properties/class
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 34d56a033c54d27b9f56e4d99f104781354fb8c0cb7df012733fc3cf9ae08b6b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0df82a45294e {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixturePresenceClass.enum:public",
            input: """
                \"public\"
                """,
            expectedError: nil
        ) { json in
            return try FixturePresenceClass(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresenceClass.enum:private",
            input: """
                \"private\"
                """,
            expectedError: nil
        ) { json in
            return try FixturePresenceClass(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresenceClass.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixturePresenceClass(wireJSON: json).wireJSON()
        },
    ]
}
