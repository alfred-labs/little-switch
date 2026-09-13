// Generated codec qualification. Do not edit.
// Source: OpenAIResponseOutput #/definitions/ResponseReasoningItem/properties/internal_chat_message_metadata_passthrough
// SDK: openai 7.15.0
// Schema SHA256: 3d68a375f7e5c82576cbd145e2eab271a10ff98cf4e1c0d1ad9b4281e2c4814f
// Projection SHA256: b519652c9df7a081147f73848e4dfead2d04e8e4f6994a22050cee1221e04013
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples1db83e60ca5f {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "OpenAIReasoningMetadata.minimal",
            input: """
                {}
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningMetadata.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"turn_id\": \"wire sample\"
                }
                """,
            expectedError: nil
        ) { json in
            return try OpenAIReasoningMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningMetadata.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try OpenAIReasoningMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningMetadata.null:turn_id",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"turn_id\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["turn_id"])
        ) { json in
            return try OpenAIReasoningMetadata(wireJSON: json).wireJSON()
        },
        .init(
            name: "OpenAIReasoningMetadata.collision",
            input: """
                {}
                """,
            expectedError: .init(.additionalFieldCollision, path: ["turn_id"])
        ) { json in
            var value = try OpenAIReasoningMetadata(wireJSON: json)
            value.additionalFields["turn_id"] = .null
            return try value.wireJSON()
        },
    ]
}
