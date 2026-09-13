// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/NullableOne
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: d1ee94f3dffcd9b7e5d961aae2ff4deafef58ed59b2569b1c2b8d46ab53335b6
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf04da140d08e {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNullableOne.minimal",
            input: """
                {
                  \"value\": \"yes\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableOne.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"value\": \"yes\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableOne.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNullableOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableOne.missing:value",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["value"])
        ) { json in
            return try FixtureNullableOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableOne.null:value",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"value\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableOne(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableOne.collision",
            input: """
                {
                  \"value\": \"yes\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["value"])
        ) { json in
            var value = try FixtureNullableOne(wireJSON: json)
            value.additionalFields["value"] = .null
            return try value.wireJSON()
        },
    ]
}
