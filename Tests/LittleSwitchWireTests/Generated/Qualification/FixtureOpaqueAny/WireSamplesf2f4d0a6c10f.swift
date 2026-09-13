// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/OpaqueAny
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 8d55288e1a0884078db4a66b2fb876f8737550b5c45055a8f5403c86b87c3bd0
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplesf2f4d0a6c10f {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureOpaqueAny.branch:0",
            input: """
                {
                  \"exact_integer\": 9007199254740993,
                  \"large_number\": 1e400,
                  \"null\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOpaqueAny(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOpaqueAny.encode-branch:0",
            input: """
                {
                  \"exact_integer\": 9007199254740993,
                  \"large_number\": 1e400,
                  \"null\": null
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureOpaqueAny.variant1(JSONValue(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureOpaqueAny.branch:1",
            input: """
                \"wire sample\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOpaqueAny(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureOpaqueAny.encode-branch:1",
            input: """
                \"wire sample\"
                """,
            expectedError: nil
        ) { json in
            return try FixtureOpaqueAny.variant2(String(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureOpaqueAny.null-union",
            input: """
                null
                """,
            expectedError: nil
        ) { json in
            return try FixtureOpaqueAny(wireJSON: json).wireJSON()
        },
    ]
}
