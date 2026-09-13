// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/UserLocation
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: cb662fa62dc86582eeda7ba693d5a7b28cc3517c2496c67a1ce665a81b793aa2
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples4991e8a180eb {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicSearchUserLocation.minimal",
            input: """
                {
                  \"type\": \"approximate\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": \"wire sample\",
                  \"country\": \"wire sample\",
                  \"region\": \"wire sample\",
                  \"timezone\": \"wire sample\",
                  \"type\": \"approximate\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.null:city",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": null,
                  \"country\": \"wire sample\",
                  \"region\": \"wire sample\",
                  \"timezone\": \"wire sample\",
                  \"type\": \"approximate\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.null:country",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": \"wire sample\",
                  \"country\": null,
                  \"region\": \"wire sample\",
                  \"timezone\": \"wire sample\",
                  \"type\": \"approximate\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.null:region",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": \"wire sample\",
                  \"country\": \"wire sample\",
                  \"region\": null,
                  \"timezone\": \"wire sample\",
                  \"type\": \"approximate\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.null:timezone",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": \"wire sample\",
                  \"country\": \"wire sample\",
                  \"region\": \"wire sample\",
                  \"timezone\": null,
                  \"type\": \"approximate\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": \"wire sample\",
                  \"country\": \"wire sample\",
                  \"region\": \"wire sample\",
                  \"timezone\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"city\": \"wire sample\",
                  \"country\": \"wire sample\",
                  \"region\": \"wire sample\",
                  \"timezone\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicSearchUserLocation(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicSearchUserLocation.collision",
            input: """
                {
                  \"type\": \"approximate\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["city"])
        ) { json in
            var value = try AnthropicSearchUserLocation(wireJSON: json)
            value.additionalFields["city"] = .null
            return try value.wireJSON()
        },
    ]
}
