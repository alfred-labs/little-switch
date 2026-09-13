// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Nested
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: f93e22af087e4e84ccb17b59bb24ea248f76514700d1fc7236749d6cae7c85f5
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesc2d7d6230096 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNested.minimal",
            input: """
                {
                  \"values\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNested(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNested.full",
            input: """
                {
                  \"values\": [
                    9007199254740993,
                    null
                  ]
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNested(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNested.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNested(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNested.missing:values",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["values"])
        ) { json in
            return try FixtureNested(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNested.null:values",
            input: """
                {
                  \"values\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["values"])
        ) { json in
            return try FixtureNested(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNested.collision",
            input: """
                {
                  \"values\": []
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["values"])
        ) { json in
            var value = try FixtureNested(wireJSON: json)
            value.additionalFields["values"] = .null
            return try value.wireJSON()
        },
        .init(
            name: "FixtureNested.forbidden-extra",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"values\": [
                    9007199254740993,
                    null
                  ]
                }
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNested(wireJSON: json).wireJSON()
        },
    ]
}
