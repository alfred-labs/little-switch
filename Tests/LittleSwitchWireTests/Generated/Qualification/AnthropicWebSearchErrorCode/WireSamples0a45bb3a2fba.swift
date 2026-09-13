// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/WebSearchToolResultErrorCode
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples0a45bb3a2fba {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicWebSearchErrorCode.enum:invalid_tool_input",
            input: """
                \"invalid_tool_input\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchErrorCode.enum:unavailable",
            input: """
                \"unavailable\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchErrorCode.enum:max_uses_exceeded",
            input: """
                \"max_uses_exceeded\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchErrorCode.enum:too_many_requests",
            input: """
                \"too_many_requests\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchErrorCode.enum:query_too_long",
            input: """
                \"query_too_long\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchErrorCode.enum:request_too_large",
            input: """
                \"request_too_large\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicWebSearchErrorCode.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicWebSearchErrorCode(wireJSON: json).wireJSON()
        },
    ]
}
