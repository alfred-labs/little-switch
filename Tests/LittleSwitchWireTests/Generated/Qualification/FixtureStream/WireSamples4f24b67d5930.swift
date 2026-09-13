// Generated codec qualification. Do not edit.
// Source: WireGenerationFixtures #/definitions/Stream
// Local qualification fixture (not an SDK contract)
// Schema SHA256: be9b2b7a4e9f5654277ce2a972a97dab6358773208b53303a62d0264df497d67
// Projection SHA256: 64f11b2129f3785391021bc6b8f28a04843c583515d6afad298e0b45b2cb61c4
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4f24b67d5930 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "FixtureStream.branch:0",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": false
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureStream(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureStream.encode-branch:0",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": false
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureStream.variant1(FixtureStreamVariant1(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureStream.branch:1",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": true
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureStream(wireJSON: json).wireJSON()
        },
        .init(
            name: "FixtureStream.encode-branch:1",
            input: """
                {
                  \"model\": \"wire sample\",
                  \"stream\": true
                }
                """,
            expectedError: nil
        ) { json in
            return try FixtureStream.variant2(FixtureStreamVariant2(wireJSON: json)).wireJSON()
        },
        .init(
            name: "FixtureStream.null-union",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try FixtureStream(wireJSON: json).wireJSON()
        },
    ]
}
