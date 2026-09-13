// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Recursive
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 04f4624eddfed58d1663253f1757792860cfed68bf91888b340391aa42838497
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples3c5d1d7047b7 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureRecursive.branch:0",
            input: """
                {
                  \"type\": \"leaf\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureRecursive(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursive.malformed-branch:0",
            input: """
                {
                  \"type\": \"leaf\"
                }
                """,
            expectedError: .init(.missingField, path: ["value"])
        ) { json in
            return try FixtureRecursive(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursive.branch:1",
            input: """
                {
                  \"child\": {
                    \"type\": \"leaf\",
                    \"value\": \"wire sample\"
                  },
                  \"type\": \"branch\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureRecursive(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursive.malformed-branch:1",
            input: """
                {
                  \"type\": \"branch\"
                }
                """,
            expectedError: .init(.missingField, path: ["child"])
        ) { json in
            return try FixtureRecursive(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursive.unknown",
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
            return try FixtureRecursive(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursive.unknown-mismatch",
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
            return try FixtureRecursive.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "FixtureRecursive.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureRecursive(wireJSON: json).wireJSON()
        },
    ]
}
