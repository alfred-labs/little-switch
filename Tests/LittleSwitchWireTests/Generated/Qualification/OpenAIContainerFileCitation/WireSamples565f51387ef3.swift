// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseOutputText.ContainerFileCitation
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples565f51387ef3 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIContainerFileCitation.minimal",
            input: """
                {
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.null:container_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": null,
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["container_id"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.null:end_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": null,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["end_index"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.null:file_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": null,
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["file_id"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.null:filename",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": null,
                  \"start_index\": 1e400,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["filename"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.null:start_index",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": null,
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["start_index"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"container_id\": \"wire sample\",
                  \"end_index\": 1e400,
                  \"file_id\": \"wire sample\",
                  \"filename\": \"wire sample\",
                  \"start_index\": 1e400,
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try OpenAIContainerFileCitation(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIContainerFileCitation.collision",
            input: """
                {
                  \"type\": \"container_file_citation\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["container_id"])
        ) { json in
            var value = try OpenAIContainerFileCitation(wireJSON: json)
            value.additionalFields["container_id"] = .null
            return try value.wireJSON()
        },
    ]
}
