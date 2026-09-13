// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/NestedOverlappingOne
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: a6c48b70d904699121cd702687c0f88e554eb2c4945e31258109a60c5e979b8f
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0b2afc93dce4 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNestedOverlap.minimal",
            input: """
                {
                  \"choice\": \"b\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNestedOverlap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlap.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choice\": \"b\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNestedOverlap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlap.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNestedOverlap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlap.missing:choice",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["choice"])
        ) { json in
            return try FixtureNestedOverlap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlap.null:choice",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"choice\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["choice"])
        ) { json in
            return try FixtureNestedOverlap(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNestedOverlap.collision",
            input: """
                {
                  \"choice\": \"b\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["choice"])
        ) { json in
            var value = try FixtureNestedOverlap(wireJSON: json)
            value.additionalFields["choice"] = .null
            return try value.wireJSON()
        },
    ]
}
