// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Recursive/oneOf/0
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 04f4624eddfed58d1663253f1757792860cfed68bf91888b340391aa42838497
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples32dcee2cdcf7 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureRecursiveLeaf.minimal",
            input: """
                {
                  \"type\": \"leaf\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"leaf\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null,
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.missing:value",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"leaf\"
                }
                """,
            expectedError: .init(.missingField, path: ["value"])
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.null:value",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"leaf\",
                  \"value\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["value"])
        ) { json in
            return try FixtureRecursiveLeaf(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureRecursiveLeaf.collision",
            input: """
                {
                  \"type\": \"leaf\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["type"])
        ) { json in
            var value = try FixtureRecursiveLeaf(wireJSON: json)
            value.additionalFields["type"] = .null
            return try value.wireJSON()
        },
    ]
}
