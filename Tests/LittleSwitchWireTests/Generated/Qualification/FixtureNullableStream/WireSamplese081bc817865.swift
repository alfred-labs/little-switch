// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/NullableStream
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: accd85355b8a637de70a05bf8609e1db772876f5353ced0b7fe751826f018502
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamplese081bc817865 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureNullableStream.branch:0",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": false
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStream(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStream.encode-branch:0",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": false
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStream.variant1(FixtureNullableStreamVariant1(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureNullableStream.branch:1",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": true
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStream(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureNullableStream.encode-branch:1",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": true
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureNullableStream.variant2(FixtureNullableStreamVariant2(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureNullableStream.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureNullableStream(wireJSON: json).wireJSON()
        },
    ]
}
