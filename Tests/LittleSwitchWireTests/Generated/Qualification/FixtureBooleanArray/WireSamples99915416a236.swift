// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/BooleanArray
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 65be1b2acc128c2d273f20ccab9d8ce2d20acd711bd4244c6ef6babbaef868d3
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples99915416a236 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureBooleanArray.minimal",
            input: """
                {
                  \"flags\": []
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanArray(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanArray.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"flags\": [
                    true
                  ]
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureBooleanArray(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanArray.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureBooleanArray(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanArray.missing:flags",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["flags"])
        ) { json in
            return try FixtureBooleanArray(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanArray.null:flags",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"flags\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["flags"])
        ) { json in
            return try FixtureBooleanArray(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureBooleanArray.collision",
            input: """
                {
                  \"flags\": []
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["flags"])
        ) { json in
            var value = try FixtureBooleanArray(wireJSON: json)
            value.additionalFields["flags"] = .null
            return try value.wireJSON()
        },
    ]
}
