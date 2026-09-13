// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Recursive/oneOf/1
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 04f4624eddfed58d1663253f1757792860cfed68bf91888b340391aa42838497
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples2d09506335f5 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureRecursiveBranch.minimal",
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
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"child\": {
                    \"type\": \"leaf\",
                    \"value\": \"wire sample\"
                  },
                  \"type\": \"branch\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.missing:child",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"branch\"
                }
                """,
            expectedError: .init(.missingField, path: ["child"])
        ) { json in
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.null:child",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"child\": null,
                  \"type\": \"branch\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["child"])
        ) { json in
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"child\": {
                    \"type\": \"leaf\",
                    \"value\": \"wire sample\"
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"child\": {
                    \"type\": \"leaf\",
                    \"value\": \"wire sample\"
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try FixtureRecursiveBranch(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveBranch.collision",
            input: """
                {
                  \"child\": {
                    \"type\": \"leaf\",
                    \"value\": \"wire sample\"
                  },
                  \"type\": \"branch\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["child"])
        ) { json in
            var value = try FixtureRecursiveBranch(wireJSON: json)
            value.additionalFields["child"] = .null
            return try value.wireJSON()
        },
    ]
}
