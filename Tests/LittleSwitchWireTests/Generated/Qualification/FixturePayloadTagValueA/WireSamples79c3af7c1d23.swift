// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/PayloadTag/anyOf/0
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 4ebbc592ec1d447a28f24bad98e3cf0854b4a7ceb621747301764e36db85822d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples79c3af7c1d23 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixturePayloadTagValueA.minimal",
            input: """
                {
                  \"__wire_payload__\": \"a\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePayloadTagValueA(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTagValueA.full",
            input: """
                {
                  \"__wire_payload__\": \"a\",
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePayloadTagValueA(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTagValueA.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixturePayloadTagValueA(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTagValueA.missing:__wire_payload__",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["__wire_payload__"])
        ) { json in
            return try FixturePayloadTagValueA(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTagValueA.null:__wire_payload__",
            input: """
                {
                  \"__wire_payload__\": null,
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["__wire_payload__"])
        ) { json in
            return try FixturePayloadTagValueA(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTagValueA.collision",
            input: """
                {
                  \"__wire_payload__\": \"a\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["__wire_payload__"])
        ) { json in
            var value = try FixturePayloadTagValueA(wireJSON: json)
            value.additionalFields["__wire_payload__"] = .null
            return try value.wireJSON()
        },
    ]
}
