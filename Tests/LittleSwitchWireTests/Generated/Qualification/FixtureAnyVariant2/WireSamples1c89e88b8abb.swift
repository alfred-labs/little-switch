// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Right
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 50de9edefaa15e236fd4eb41da47d47029f2ef63a263c79d7fcdf60524cf8770
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1c89e88b8abb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureAnyVariant2.minimal",
            input: """
                {
                  \"right\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureAnyVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAnyVariant2.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"right\": 1e400
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureAnyVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAnyVariant2.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureAnyVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAnyVariant2.missing:right",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["right"])
        ) { json in
            return try FixtureAnyVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAnyVariant2.null:right",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"right\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["right"])
        ) { json in
            return try FixtureAnyVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureAnyVariant2.collision",
            input: """
                {
                  \"right\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["right"])
        ) { json in
            var value = try FixtureAnyVariant2(wireJSON: json)
            value.additionalFields["right"] = .null
            return try value.wireJSON()
        },
    ]
}
