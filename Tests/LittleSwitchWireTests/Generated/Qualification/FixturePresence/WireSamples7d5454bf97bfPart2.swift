// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Presence
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 34d56a033c54d27b9f56e4d99f104781354fb8c0cb7df012733fc3cf9ae08b6b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7d5454bf97bfPart2 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixturePresence.null:presence",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": null,
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.missing:required",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["required"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.null:required",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["required"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.collision",
            input: """
                {
                  \"amount\": 9007199254740993,
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["amount"])
        ) { json in
            var value = try FixturePresence(wireJSON: json)
            value.additionalFields["amount"] = .null
            return try value.wireJSON()
        },
    ]
}
