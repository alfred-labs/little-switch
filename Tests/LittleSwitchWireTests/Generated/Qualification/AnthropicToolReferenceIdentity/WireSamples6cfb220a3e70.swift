// Generated codec qualification. Do not edit.
// Source: AnthropicCountTokensRequest #/definitions/ToolReferenceBlockParam
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: 967c7ae1768ff5700b38a6cb5328610dc9e3a7ea26c787dde6f21985d2bd1106
// Projection SHA256: 6ab17812d982531c6d82a27a80816a5b336174942e2e86082ebbd7d0200b5cde
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples6cfb220a3e70 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicToolReferenceIdentity.minimal",
            input: """
                {
                  \"tool_name\": \"wire sample\",
                  \"type\": \"tool_reference\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.full",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_name\": \"wire sample\",
                  \"type\": \"tool_reference\"
                }
                """,
            expectedError: nil
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.invalid-root",
            input: """
                null
                """,
            expectedError: .init(.typeMismatch, path: [])
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.missing:tool_name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"type\": \"tool_reference\"
                }
                """,
            expectedError: .init(.missingField, path: ["tool_name"])
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.null:tool_name",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_name\": null,
                  \"type\": \"tool_reference\"
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["tool_name"])
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.missing:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_name\": \"wire sample\"
                }
                """,
            expectedError: .init(.missingField, path: ["type"])
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.null:type",
            input: """
                {
                  \"__wire_unknown__\": {
                    \"exact_integer\": 9007199254740993,
                    \"large_number\": 1e400,
                    \"null\": null
                  },
                  \"tool_name\": \"wire sample\",
                  \"type\": null
                }
                """,
            expectedError: .init(.unexpectedNull, path: ["type"])
        ) { json in
            return try AnthropicToolReferenceIdentity(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicToolReferenceIdentity.collision",
            input: """
                {
                  \"tool_name\": \"wire sample\",
                  \"type\": \"tool_reference\"
                }
                """,
            expectedError: .init(.additionalFieldCollision, path: ["tool_name"])
        ) { json in
            var value = try AnthropicToolReferenceIdentity(wireJSON: json)
            value.additionalFields["tool_name"] = .null
            return try value.wireJSON()
        },
    ]
}
