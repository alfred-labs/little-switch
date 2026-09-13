// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/NullableStream/anyOf/0
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: accd85355b8a637de70a05bf8609e1db772876f5353ced0b7fe751826f018502
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesb35c1746967f {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNullableStreamVariant1.minimal",
            input: """
                {
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStreamVariant1(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"stream\": false
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStreamVariant1(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNullableStreamVariant1(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1.missing:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"stream\": false
                }
                """,
            expectedError: .init(.missingField, path: ["model"])
        ) { json in
            return try FixtureNullableStreamVariant1(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1.null:model",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": null,
                  \"stream\": false
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["model"])
        ) { json in
            return try FixtureNullableStreamVariant1(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1.null:stream",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"model\": \"wire sample\",
                  \"stream\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStreamVariant1(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStreamVariant1.collision",
            input: """
                {
                  \"model\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["model"])
        ) { json in
            var value = try FixtureNullableStreamVariant1(wireJSON: json)
            value.additionalFields["model"] = .null
            return try value.wireJSON()
        },
    ]
}
