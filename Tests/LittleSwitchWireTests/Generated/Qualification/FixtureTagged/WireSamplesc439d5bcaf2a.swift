// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Tagged
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: c99ce03793b5a91196f7bb3e0422a47aae02dadb5492bfd53a040e33c6fc843c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc439d5bcaf2a {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureTagged.branch:0",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTagged(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTagged.malformed-branch:0",
            input: """
                {
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try FixtureTagged(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTagged.branch:1",
            input: """
                {
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTagged(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTagged.malformed-branch:1",
            input: """
                {
                  \"type\": \"tool\"
                }
                """,
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try FixtureTagged(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTagged.unknown",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTagged(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTagged.unknown-mismatch",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"__wire_unknown__\"
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixtureTagged.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "FixtureTagged.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureTagged(wireJSON: json).wireJSON()
        },
    ]
}
