// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Right
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: a812c98cb118986835fa5d1a4b4525a05af563aea5c9014738b4f2d3b478aa73
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples6065cd12f089 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureOneVariant2.minimal",
            input: """
                {
                  \"right\": 9007199254740993
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOneVariant2.full",
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
            return try FixtureOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOneVariant2.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOneVariant2.missing:right",
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
            return try FixtureOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOneVariant2.null:right",
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
            return try FixtureOneVariant2(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOneVariant2.collision",
            input: """
                {
                  \"right\": 9007199254740993
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["right"])
        ) { json in
            var value = try FixtureOneVariant2(wireJSON: json)
            value.additionalFields["right"] = .null
            return try value.wireJSON()
        },
    ]
}
