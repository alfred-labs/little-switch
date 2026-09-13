// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/LocalNames
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 8a7b8dd9efb90e9b917c4d9fe8765cb060154ba3f6c1a312be206ae9c086a7b3
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesef3d6aaa45f8 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureLocalNames.minimal",
            input: """
                {
                  \"object\": \"wire sample\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"wire sample\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.missing:object",
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
            expectedError: .init(.missingField, path: ["object"])
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.null:object",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": null,
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["object"])
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.missing:value",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["value"])
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.null:value",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"object\": \"wire sample\",
                  \"value\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["value"])
        ) { json in
            return try FixtureLocalNames(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureLocalNames.collision",
            input: """
                {
                  \"object\": \"wire sample\",
                  \"value\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["object"])
        ) { json in
            var value = try FixtureLocalNames(wireJSON: json)
            value.additionalFields["object"] = .null
            return try value.wireJSON()
        },
    ]
}
