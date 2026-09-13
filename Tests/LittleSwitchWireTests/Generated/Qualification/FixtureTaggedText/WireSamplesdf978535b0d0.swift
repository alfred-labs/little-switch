// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Text
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: c99ce03793b5a91196f7bb3e0422a47aae02dadb5492bfd53a040e33c6fc843c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesdf978535b0d0 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureTaggedText.minimal",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.missing:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.missingField, path: ["text"])
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.null:text",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": null,
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["text"])
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"text\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try FixtureTaggedText(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedText.collision",
            input: """
                {
                  \"text\": \"wire sample\",
                  \"type\": \"text\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["text"])
        ) { json in
            var value = try FixtureTaggedText(wireJSON: json)
            value.additionalFields["text"] = .null
            return try value.wireJSON()
        },
    ]
}
