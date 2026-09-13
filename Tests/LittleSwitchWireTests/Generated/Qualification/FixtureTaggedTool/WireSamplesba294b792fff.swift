// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Tool
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: c99ce03793b5a91196f7bb3e0422a47aae02dadb5492bfd53a040e33c6fc843c
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesba294b792fff {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureTaggedTool.minimal",
            input: """
                {
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.missing:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool\"
                }
                """,
            expectedError: .init(.missingField, path: ["input"])
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.null:input",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": null,
                  \"type\": \"tool\"
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  }
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try FixtureTaggedTool(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureTaggedTool.collision",
            input: """
                {
                  \"input\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["input"])
        ) { json in
            var value = try FixtureTaggedTool(wireJSON: json)
            value.additionalFields["input"] = .null
            return try value.wireJSON()
        },
    ]
}
