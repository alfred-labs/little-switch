// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Projection
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 89033e4b3c8101ff8dcc183c9a63f729a16a830a38986872b8d263a367608a50
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples5a6e5bfc9523 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureProjection.minimal",
            input: """
                {
                  \"kept\": \"wire sample\",
                  \"type\": \"projected\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"kept\": \"wire sample\",
                  \"type\": \"projected\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.missing:kept",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"projected\"
                }
                """,
            expectedError: .init(.missingField, path: ["kept"])
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.null:kept",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"kept\": null,
                  \"type\": \"projected\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["kept"])
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"kept\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"kept\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try FixtureProjection(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureProjection.collision",
            input: """
                {
                  \"kept\": \"wire sample\",
                  \"type\": \"projected\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["kept"])
        ) { json in
            var value = try FixtureProjection(wireJSON: json)
            value.additionalFields["kept"] = .null
            return try value.wireJSON()
        },
    ]
}
