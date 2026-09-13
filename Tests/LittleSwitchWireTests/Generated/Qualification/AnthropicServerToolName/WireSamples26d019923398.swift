// Generated codec qualification. Do not edit.
// Source: AnthropicMessage #/definitions/ServerToolUseBlock/properties/name/compatibility/anthropic-anthropiccontentblock-servertooluseblock-name-openenum/known
// SDK: @anthropic-ai/sdk 0.125.0
// Schema SHA256: f3d6590b05383bf69d231c217479804894e4d3ecce848304e0f034315771ec29
// Projection SHA256: 34d1068d239cbf4d5a4678bcddec4fdbdb304592f0949638890254a9b99bb8eb
// Compatibility SHA256: 17e6bf03d47495b1904e64676ea4fbca8f481e5a3d8aee3b4fb0b8be4ead52df
import LittleSwitchWire

enum WireSamples26d019923398 {
    static let samples: [WireGeneratedSample] = [
        .init(
            name: "AnthropicServerToolName.enum:web_search",
            input: """
                \"web_search\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.enum:web_fetch",
            input: """
                \"web_fetch\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.enum:code_execution",
            input: """
                \"code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.enum:bash_code_execution",
            input: """
                \"bash_code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.enum:text_editor_code_execution",
            input: """
                \"text_editor_code_execution\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.enum:tool_search_tool_regex",
            input: """
                \"tool_search_tool_regex\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.enum:tool_search_tool_bm25",
            input: """
                \"tool_search_tool_bm25\"
                """,
            expectedError: nil
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
        .init(
            name: "AnthropicServerToolName.invalid-enum",
            input: """
                \"__wire_unknown__\"
                """,
            expectedError: .init(.invalidDiscriminator, path: [])
        ) { json in
            return try AnthropicServerToolName(wireJSON: json).wireJSON()
        },
    ]
}
