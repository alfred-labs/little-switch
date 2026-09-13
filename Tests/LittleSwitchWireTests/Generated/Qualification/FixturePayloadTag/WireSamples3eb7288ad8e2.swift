// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/PayloadTag
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 4ebbc592ec1d447a28f24bad98e3cf0854b4a7ceb621747301764e36db85822d
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples3eb7288ad8e2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixturePayloadTag.branch:0",
            input: """
                {
                  \"__wire_payload__\": \"a\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePayloadTag(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTag.branch:1",
            input: """
                {
                  \"__wire_payload__\": \"b\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePayloadTag(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTag.unknown",
            input: """
                {
                  \"__wire_payload__\": \"__wire_unknown__\",
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePayloadTag(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTag.unknown-mismatch",
            input: """
                {
                  \"__wire_payload__\": \"__wire_unknown__\",
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try FixturePayloadTag.unknown(type: "__wire_unknown___mismatch", payload: json).wireJSON()
        },
        .init(
            name: "FixturePayloadTag.missing-tag",
            input: """
                {}
                """,
            expectedError: .init(.missingField, path: ["__wire_payload__"])
        ) { json in
            return try FixturePayloadTag(wireJSON: json).wireJSON()
        },
    ]
}
