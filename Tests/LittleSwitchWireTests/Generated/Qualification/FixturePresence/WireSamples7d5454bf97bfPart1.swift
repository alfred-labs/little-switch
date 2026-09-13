// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Presence
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 34d56a033c54d27b9f56e4d99f104781354fb8c0cb7df012733fc3cf9ae08b6b
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples7d5454bf97bfPart1 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixturePresence.minimal",
            input: """
                {
                  \"amount\": 9007199254740993,
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.full",
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
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.missing:amount",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["amount"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.null:amount",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": null,
                  \"class\": \"public\",
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["amount"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.missing:class",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["class"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.null:class",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"class\": null,
                  \"nullable\": \"wire sample\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["class"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.missing:nullable",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"class\": \"public\",
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["nullable"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.null:nullable",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"amount\": 1e400,
                  \"class\": \"public\",
                  \"nullable\": null,
                  \"optional\": \"wire sample\",
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixturePresence.null:optional",
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
                  \"optional\": null,
                  \"presence\": \"wire sample\",
                  \"required\": \"wire sample\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["optional"])
        ) { json in
            return try FixturePresence(wireJSON: json).wireJSON()
        },
    ]
}
